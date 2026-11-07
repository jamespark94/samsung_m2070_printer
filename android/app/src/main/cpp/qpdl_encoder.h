#ifndef QPDL_ENCODER_H
#define QPDL_ENCODER_H

#include <vector>
#include <cstdint>
#include <string>

class QpdlEncoder {
public:
    static std::vector<uint8_t> createJobStartHeader(const std::string& jobName = "Document.pdf");
    static std::vector<uint8_t> createJobEndFooter();
    
    // Page start record (17 bytes: 0x00 ...)
    // width300 and height300 are paper dimensions in 1/300 inch units (e.g. 2480 x 3508 for A4)
    static std::vector<uint8_t> createPageHeader(int width300, int height300, int copies = 1, int resolutionDpi = 600);
    
    // Page end record (3 bytes: 0x01 ...)
    static std::vector<uint8_t> createPageFooter(int copies = 1);
    
    // Encodes 1-bit packed mono bitmap buffer (width x height) using Samsung Algo 0x11
    // split into standard 128-row bands in column-major, inverted format (1 = white, 0 = black/toner).
    static std::vector<uint8_t> encodePageBandsAlgo0x11(const uint8_t* monoBits, int width, int height, int resolutionDpi = 600);

    // Dither or threshold ARGB_8888 pixels into 1-bit packed mono buffer
    // monoBits output buffer must be allocated with size = ((width + 7) / 8) * height
    static void convertArgbToMono(const uint32_t* argbPixels, int width, int height, uint8_t* monoBits, bool useDithering);

private:
    // Core Algo 0x11 compressor
    static bool compressAlgo0x11(const uint8_t* inData, uint32_t inSize, std::vector<uint8_t>& outData);
    static void lookupBestOccurs(const uint8_t* data, uint32_t size, uint16_t* ptrArray);
};

#endif // QPDL_ENCODER_H
