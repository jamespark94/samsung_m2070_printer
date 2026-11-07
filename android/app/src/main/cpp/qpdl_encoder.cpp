#include "qpdl_encoder.h"
#include <cstring>
#include <algorithm>
#include <sstream>
#include <cstdlib>

// Constants for Samsung Algo 0x11 Compression
static constexpr uint32_t COMPRESS_SAMPLE_RATE = 0x800; // 2048
static constexpr uint32_t TABLE_PTR_SIZE = 0x40;         // 64 offsets
static constexpr uint32_t MAX_UNCOMPRESSED_BYTES = 0x80; // 128
static constexpr uint32_t MAX_COMPRESSED_BYTES = 0x202;   // 514
static constexpr uint32_t MIN_COMPRESSED_BYTES = 0x2;
static constexpr uint8_t  COMPRESSION_FLAG = 0x80;

std::vector<uint8_t> QpdlEncoder::createJobStartHeader(const std::string& jobName) {
    std::ostringstream oss;
    // Standard Samsung SPL / QPDL v3 PJL wrapper
    // Note: \n line endings matching SpliX / ULD output
    oss << "\x1B%-12345X@PJL DEFAULT SERVICEDATE=20261107\n";
    oss << "@PJL SET USERNAME=\"Android\"\n";
    oss << "@PJL SET JOBNAME=\"" << jobName << "\"\n";
    oss << "@PJL SET PAPERTYPE=OFF\n";
    oss << "@PJL SET ALTITUDE=LOW\n";
    oss << "@PJL SET DENSITY=3\n";
    oss << "@PJL SET RET=NORMAL\n";
    oss << "@PJL ENTER LANGUAGE = QPDL\n";

    std::string str = oss.str();
    return std::vector<uint8_t>(str.begin(), str.end());
}

std::vector<uint8_t> QpdlEncoder::createJobEndFooter() {
    std::vector<uint8_t> out;
    // Standard QPDL Job Terminate: 0x09 followed by UEL
    out.push_back(0x09);

    std::string pjl = "\x1B%-12345X";
    out.insert(out.end(), pjl.begin(), pjl.end());
    return out;
}

std::vector<uint8_t> QpdlEncoder::createPageHeader(int width300, int height300, int copies, int resolutionDpi) {
    std::vector<uint8_t> h(17, 0);
    // Page Record Type: 0x00
    h[0x0] = 0x00; 

    // Resolution / 100 (6 = 600 DPI, 3 = 300 DPI, 12 = 1200 DPI)
    uint8_t resVal = static_cast<uint8_t>(resolutionDpi / 100);
    if (resVal == 0) resVal = 6;
    h[0x1] = resVal; // Y Resolution

    // Copies (uint16 Big-Endian)
    h[0x2] = static_cast<uint8_t>((copies >> 8) & 0xFF);
    h[0x3] = static_cast<uint8_t>(copies & 0xFF);

    // Paper type: 2 = A4 (0 = Letter, 1 = Legal, 2 = A4, 21 = Custom)
    h[0x4] = 0x02;

    // Paper Dimensions in 1/300 inch at all resolutions (standard QPDL v3 / SpliX / ULD)
    h[0x5] = static_cast<uint8_t>((width300 >> 8) & 0xFF);
    h[0x6] = static_cast<uint8_t>(width300 & 0xFF);
    h[0x7] = static_cast<uint8_t>((height300 >> 8) & 0xFF);
    h[0x8] = static_cast<uint8_t>(height300 & 0xFF);

    h[0x9] = 0x01;  // Paper source: 1 = Auto Tray
    h[0xa] = 0x00;  // Reserved
    h[0xb] = 0x00;  // Duplex: 0 = Off
    h[0xc] = 0x00;  // Tumble: 0 = Off
    h[0xd] = 0x00;  // Reserved
    h[0xe] = 0x03;  // QPDL Version: 3 (SL-M2070 / SL-M2020)
    h[0xf] = 0x01;  // Sub-version: 1
    h[0x10] = resVal; // X Resolution

    return h;
}

std::vector<uint8_t> QpdlEncoder::createPageFooter(int copies) {
    std::vector<uint8_t> f(3, 0);
    f[0] = 0x01; // Record type: Page end
    f[1] = static_cast<uint8_t>((copies >> 8) & 0xFF);
    f[2] = static_cast<uint8_t>(copies & 0xFF);
    return f;
}

// Compare function for qsort in occurrence counter (biggest count first)
static int compareOccurs(const void* n1, const void* n2) {
    const uint32_t* a = reinterpret_cast<const uint32_t*>(n1);
    const uint32_t* b = reinterpret_cast<const uint32_t*>(n2);
    if (b[0] != a[0]) {
        return (b[0] > a[0]) ? 1 : -1;
    }
    return 0;
}

void QpdlEncoder::lookupBestOccurs(const uint8_t* data, uint32_t size, uint16_t* ptrArray) {
    uint32_t occurs[COMPRESS_SAMPLE_RATE][2];
    for (uint32_t i = 0; i < COMPRESS_SAMPLE_RATE; ++i) {
        occurs[i][0] = 0;
        occurs[i][1] = i;
    }

    for (uint32_t i = COMPRESS_SAMPLE_RATE; i < size; i += COMPRESS_SAMPLE_RATE) {
        uint8_t b = data[i];
        for (uint32_t j = 1; j < COMPRESS_SAMPLE_RATE; ++j) {
            if (data[i - j] == b) {
                occurs[j - 1][0]++;
            }
        }
    }

    qsort(occurs, COMPRESS_SAMPLE_RATE, sizeof(uint32_t) * 2, compareOccurs);

    bool oneIsPresent = false;
    for (uint32_t i = 0; i < TABLE_PTR_SIZE; ++i) {
        ptrArray[i] = static_cast<uint16_t>(occurs[i][1] + 1);
        if (ptrArray[i] == 1) {
            oneIsPresent = true;
        }
    }
    if (!oneIsPresent) {
        ptrArray[TABLE_PTR_SIZE - 1] = 1;
    }
}

bool QpdlEncoder::compressAlgo0x11(const uint8_t* inData, uint32_t inSize, std::vector<uint8_t>& outData) {
    if (!inData || inSize == 0) return false;

    uint16_t ptrArray[TABLE_PTR_SIZE];
    lookupBestOccurs(inData, inSize, ptrArray);

    std::vector<uint8_t> out(inSize + 256);
    uint32_t w = 4;
    uint32_t uncompSize = 0;

    // 1. Write the 64-entry offset table (128 bytes Little-Endian)
    for (uint32_t i = 0; i < TABLE_PTR_SIZE; ++i, w += 2) {
        out[w] = static_cast<uint8_t>(ptrArray[i] & 0xFF);
        out[w + 1] = static_cast<uint8_t>((ptrArray[i] >> 8) & 0xFF);
        if (ptrArray[i] > uncompSize) {
            uncompSize = ptrArray[i];
        }
    }

    // 2. Write the uncompressed prefix length (uint32 Little-Endian) at out[0..3]
    if (uncompSize > MAX_UNCOMPRESSED_BYTES) {
        uncompSize = MAX_UNCOMPRESSED_BYTES;
    }
    if (uncompSize > inSize) {
        uncompSize = inSize;
    }
    out[0] = static_cast<uint8_t>(uncompSize & 0xFF);
    out[1] = static_cast<uint8_t>((uncompSize >> 8) & 0xFF);
    out[2] = static_cast<uint8_t>((uncompSize >> 16) & 0xFF);
    out[3] = static_cast<uint8_t>((uncompSize >> 24) & 0xFF);

    // Write uncompressed prefix bytes
    uint32_t r = 0;
    for (; r < uncompSize; ++r, ++w) {
        out[w] = inData[r];
    }

    // 3. Main LZS compression loop
    uint32_t rawDataCounter = 0;
    uint32_t rawDataCounterPtr = 0;
    const uint32_t maxOutputSize = static_cast<uint32_t>(out.size());

    while (r < inSize) {
        uint32_t maxCompSize = inSize - r;
        if (maxCompSize > MAX_COMPRESSED_BYTES) {
            maxCompSize = MAX_COMPRESSED_BYTES;
        }

        if (maxCompSize >= 2) {
            uint32_t bestCompCounter = 0;
            uint32_t bestPtr = 0;

            if (w + 2 >= maxOutputSize) {
                return false;
            }

            for (uint32_t i = 0; i < TABLE_PTR_SIZE; ++i) {
                if (ptrArray[i] > r) continue;
                uint32_t rTmp = r - ptrArray[i];
                uint32_t counter = 0;
                while (counter < maxCompSize && inData[r + counter] == inData[rTmp + counter]) {
                    counter++;
                }
                if (counter > bestCompCounter) {
                    bestCompCounter = counter;
                    bestPtr = i;
                }
            }

            if (bestCompCounter > MIN_COMPRESSED_BYTES) {
                r += bestCompCounter;
                bestCompCounter -= 3;
                out[w] = static_cast<uint8_t>(COMPRESSION_FLAG | (bestCompCounter & 0x7F));
                out[w + 1] = static_cast<uint8_t>(((bestCompCounter >> 1) & 0xC0) | (bestPtr & 0x3F));
                w += 2;
                if (rawDataCounter) {
                    out[rawDataCounterPtr] = static_cast<uint8_t>(rawDataCounter - 1);
                    rawDataCounter = 0;
                }
                continue;
            }
        }

        // Write uncompressed literal byte
        rawDataCounter++;
        if (rawDataCounter == 1) {
            if (w + 2 >= maxOutputSize) return false;
            rawDataCounterPtr = w;
            w++;
        } else if (rawDataCounter == MAX_UNCOMPRESSED_BYTES) {
            out[rawDataCounterPtr] = 0x7F;
            rawDataCounter = 0;
        }
        out[w] = inData[r];
        w++;
        r++;
    }

    if (rawDataCounter) {
        out[rawDataCounterPtr] = static_cast<uint8_t>(rawDataCounter - 1);
    }

    outData.assign(out.begin(), out.begin() + w);
    return true;
}

std::vector<uint8_t> QpdlEncoder::encodePageBandsAlgo0x11(const uint8_t* monoBits, int width, int height, int resolutionDpi) {
    std::vector<uint8_t> pagePayload;
    
    // SpliX & ULD standard: 128 rows per band
    const size_t bandHeight = 128;
    const size_t rowBytes = (width + 7) / 8;
    
    // Printable width rounded up to 32 bytes (matches HP / Samsung standard per-paper band width)
    // Formula: ceil((width_px - dpi/3) / 8) rounded up to multiple of 32
    // For A4 @ 600 DPI (width=4960): (4960 - 200)/8 = 595 -> ceil + 31 & ~31 = 608 bytes
    // For A4 @ 300 DPI (width=2480): (2480 - 100)/8 = 297.5 -> 298 -> 320 bytes
    double bytesDouble = (width - resolutionDpi / 3.0) / 8.0;
    size_t bandBytes = (static_cast<size_t>(std::ceil(bytesDouble)) + 31) & ~31;
    if (bandBytes < rowBytes) {
        bandBytes = (rowBytes + 31) & ~31;
    }

    const size_t copyBytes = std::min(rowBytes, bandBytes);
    const int totalBands = (height + bandHeight - 1) / bandHeight;

    // Allocate temporary buffer for transposing band to column-major inverted
    std::vector<uint8_t> packed(bandBytes * bandHeight, 0xFF);

    for (int b = 0; b < totalBands; ++b) {
        int startY = b * bandHeight;
        int currentBandH = std::min(static_cast<int>(bandHeight), height - startY);

        // Check if the band in input monoBits has any black toner pixels
        // In monoBits: bit 1 = black toner, 0 = white paper
        bool isBlank = true;
        for (int y = 0; y < currentBandH; ++y) {
            const uint8_t* rowSrc = monoBits + ((startY + y) * rowBytes);
            for (size_t x = 0; x < copyBytes; ++x) {
                if (rowSrc[x] != 0) {
                    isBlank = false;
                    break;
                }
            }
            if (!isBlank) break;
        }

        // QPDL v3 / SL-M2020/M2070 skips completely blank bands entirely!
        if (isBlank) {
            continue;
        }

        // Transpose to column-major layout and invert (1 = white, 0 = black toner)
        // Each column x from 0..bandBytes-1 has 128 vertical bytes (y from 0..127)
        // If row is past currentBandH (end of page) or column is past copyBytes, it's white (0xFF).
        for (size_t x = 0; x < bandBytes; ++x) {
            for (size_t y = 0; y < bandHeight; ++y) {
                if (x < copyBytes && static_cast<int>(y) < currentBandH) {
                    uint8_t rowVal = monoBits[(startY + y) * rowBytes + x];
                    // Invert: 1 in monoBits (toner) -> 0, 0 in monoBits (white) -> 1
                    packed[x * bandHeight + y] = static_cast<uint8_t>(~rowVal);
                } else {
                    packed[x * bandHeight + y] = 0xFF; // White background
                }
            }
        }

        uint32_t packedSize = static_cast<uint32_t>(bandBytes * bandHeight);
        std::vector<uint8_t> compData;
        if (!compressAlgo0x11(packed.data(), packedSize, compData)) {
            compData.assign(packed.begin(), packed.end());
        }

        // QPDL Record 0x0C for Band:
        // Header layout (11 bytes):
        // [0] 0x0C (Signature)
        // [1] Band number (uint8)
        // [2..3] Width in bits (uint16 BE) = bandBytes * 8
        // [4..5] Height in rows (uint16 BE) = bandHeight (128)
        // [6] Compression: 0x11
        // [7..10] Total Record Data Size (uint32 BE): compData.size() + 4 (signature) + 4 (checksum)
        uint16_t bandWidthBits = static_cast<uint16_t>(bandBytes * 8);
        uint16_t bandH16 = static_cast<uint16_t>(bandHeight);
        uint32_t dataSize = static_cast<uint32_t>(compData.size() + 4 + 4);

        std::vector<uint8_t> bandRecord;
        bandRecord.reserve(11 + 4 + compData.size() + 4);
        bandRecord.push_back(0x0C);
        bandRecord.push_back(static_cast<uint8_t>(b & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((bandWidthBits >> 8) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>(bandWidthBits & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((bandH16 >> 8) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>(bandH16 & 0xFF));
        bandRecord.push_back(0x11); // Compression algorithm 0x11

        bandRecord.push_back(static_cast<uint8_t>((dataSize >> 24) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((dataSize >> 16) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((dataSize >> 8) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>(dataSize & 0xFF));

        // Sub-header signature (4 bytes Little-Endian for Algo 0x11): 0x09ABCDEF -> [0xEF, 0xCD, 0xAB, 0x09]
        const uint8_t sig[4] = { 0xEF, 0xCD, 0xAB, 0x09 };
        bandRecord.push_back(sig[0]);
        bandRecord.push_back(sig[1]);
        bandRecord.push_back(sig[2]);
        bandRecord.push_back(sig[3]);

        // Append compressed payload data
        bandRecord.insert(bandRecord.end(), compData.begin(), compData.end());

        // Calculate Checksum = sum of sub-header signature bytes (0xEF+0xCD+0xAB+0x09) + sum of payload bytes
        uint32_t checksum = static_cast<uint32_t>(sig[0]) + sig[1] + sig[2] + sig[3];
        for (uint8_t byteVal : compData) {
            checksum += byteVal;
        }

        // Append Checksum (4 bytes Big-Endian)
        bandRecord.push_back(static_cast<uint8_t>((checksum >> 24) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((checksum >> 16) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>((checksum >> 8) & 0xFF));
        bandRecord.push_back(static_cast<uint8_t>(checksum & 0xFF));

        pagePayload.insert(pagePayload.end(), bandRecord.begin(), bandRecord.end());
    }

    return pagePayload;
}

void QpdlEncoder::convertArgbToMono(const uint32_t* argbPixels, int width, int height, uint8_t* monoBits, bool useDithering) {
    int lineStride = (width + 7) / 8;
    // monoBits: 1 = black toner, 0 = white background
    std::memset(monoBits, 0, lineStride * height);

    if (!useDithering) {
        // Fast thresholding (Threshold = 128)
        // Dark pixels (< 128) -> Bit 1 (Toner applied)
        for (int y = 0; y < height; ++y) {
            const uint32_t* srcRow = argbPixels + (y * width);
            uint8_t* dstRow = monoBits + (y * lineStride);

            for (int x = 0; x < width; ++x) {
                uint32_t p = srcRow[x];
                uint32_t r = (p >> 16) & 0xFF;
                uint32_t g = (p >> 8) & 0xFF;
                uint32_t b = p & 0xFF;
                uint32_t lum = (r * 77 + g * 150 + b * 29) >> 8;
                
                if (lum < 128) {
                    dstRow[x >> 3] |= (0x80 >> (x & 7));
                }
            }
        }
    } else {
        // Floyd-Steinberg dithering
        std::vector<int16_t> currentErr(width + 2, 0);
        std::vector<int16_t> nextErr(width + 2, 0);

        for (int y = 0; y < height; ++y) {
            const uint32_t* srcRow = argbPixels + (y * width);
            uint8_t* dstRow = monoBits + (y * lineStride);
            std::fill(nextErr.begin(), nextErr.end(), 0);

            for (int x = 0; x < width; ++x) {
                uint32_t p = srcRow[x];
                uint32_t r = (p >> 16) & 0xFF;
                uint32_t g = (p >> 8) & 0xFF;
                uint32_t b = p & 0xFF;
                int lum = static_cast<int>((r * 77 + g * 150 + b * 29) >> 8);

                lum += currentErr[x + 1];
                if (lum < 0) lum = 0;
                if (lum > 255) lum = 255;

                int outBit = (lum < 128) ? 1 : 0;
                if (outBit == 1) {
                    dstRow[x >> 3] |= (0x80 >> (x & 7));
                }

                int targetLum = (outBit == 1) ? 0 : 255;
                int err = lum - targetLum;

                currentErr[x + 2] += (err * 7) / 16;
                nextErr[x]     += (err * 3) / 16;
                nextErr[x + 1] += (err * 5) / 16;
                nextErr[x + 2] += (err * 1) / 16;
            }

            currentErr = nextErr;
        }
    }
}
