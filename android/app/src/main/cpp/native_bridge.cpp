#include <jni.h>
#include <android/bitmap.h>
#include <android/log.h>
#include <vector>
#include "qpdl_encoder.h"

#define LOG_TAG "SPL_NATIVE"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_MainActivity_nativeGetJobStartHeader(
        JNIEnv* env, jobject /* this */, jstring jobName) {
    const char* cJobName = env->GetStringUTFChars(jobName, nullptr);
    std::string strJobName = cJobName ? cJobName : "Document.pdf";
    if (cJobName) env->ReleaseStringUTFChars(jobName, cJobName);

    std::vector<uint8_t> bytes = QpdlEncoder::createJobStartHeader(strJobName);
    jbyteArray result = env->NewByteArray(static_cast<jsize>(bytes.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<const jbyte*>(bytes.data()));
    return result;
}

JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_MainActivity_nativeGetJobEndFooter(
        JNIEnv* env, jobject /* this */) {
    std::vector<uint8_t> bytes = QpdlEncoder::createJobEndFooter();
    jbyteArray result = env->NewByteArray(static_cast<jsize>(bytes.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<const jbyte*>(bytes.data()));
    return result;
}

JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_MainActivity_nativeEncodeBitmapPage(
        JNIEnv* env, jobject /* this */, jobject bitmap, jint copies, jint resolutionDpi, jboolean useDithering) {
    
    AndroidBitmapInfo info;
    if (AndroidBitmap_getInfo(env, bitmap, &info) < 0) {
        LOGE("Failed to get bitmap info");
        return nullptr;
    }

    if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {
        LOGE("Bitmap format is not RGBA_8888 (%d)", info.format);
        return nullptr;
    }

    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) < 0) {
        LOGE("Failed to lock bitmap pixels");
        return nullptr;
    }

    int width = static_cast<int>(info.width);
    int height = static_cast<int>(info.height);
    int lineStride = (width + 7) / 8;
    size_t monoSize = static_cast<size_t>(lineStride) * height;

    std::vector<uint8_t> monoBits(monoSize);

    // 1. Dither / Threshold ARGB to 1-Bit packed mono
    QpdlEncoder::convertArgbToMono(reinterpret_cast<const uint32_t*>(pixels), width, height, monoBits.data(), useDithering);

    AndroidBitmap_unlockPixels(env, bitmap);

    // 2. Build full QPDL v3 Page:
    // Header (Record 0x00) with 1/300-inch grid dimensions (A4 is 2480 x 3508)
    int width300 = static_cast<int>(std::round(width * 300.0 / resolutionDpi));
    int height300 = static_cast<int>(std::round(height * 300.0 / resolutionDpi));
    std::vector<uint8_t> pageHeader = QpdlEncoder::createPageHeader(width300, height300, copies, resolutionDpi);
    std::vector<uint8_t> bandData = QpdlEncoder::encodePageBandsAlgo0x11(monoBits.data(), width, height, resolutionDpi);
    std::vector<uint8_t> pageFooter = QpdlEncoder::createPageFooter(copies);

    std::vector<uint8_t> fullPage;
    fullPage.reserve(pageHeader.size() + bandData.size() + pageFooter.size());
    fullPage.insert(fullPage.end(), pageHeader.begin(), pageHeader.end());
    fullPage.insert(fullPage.end(), bandData.begin(), bandData.end());
    fullPage.insert(fullPage.end(), pageFooter.begin(), pageFooter.end());

    LOGI("Encoded page %dx%d with Algo 0x11: monoBytes=%zu, fullPageBytes=%zu", width, height, monoSize, fullPage.size());

    jbyteArray result = env->NewByteArray(static_cast<jsize>(fullPage.size()));
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(fullPage.size()), reinterpret_cast<const jbyte*>(fullPage.data()));
    return result;
}

}
