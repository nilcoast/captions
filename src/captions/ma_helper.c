/**
 * Thin C wrapper around miniaudio for Nim interop.
 * Hides miniaudio's large structs behind an opaque API.
 */

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <string.h>
#include <stdlib.h>

typedef void (*MaSamplesCallback)(const float* data, int count, void* userdata);

typedef struct {
    ma_context context;
    ma_device device;
    MaSamplesCallback callback;
    void* userdata;
    int context_initialized;
    int device_initialized;
} MaCapture;

static void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pOutput;
    MaCapture* cap = (MaCapture*)pDevice->pUserData;
    if (cap && cap->callback && pInput) {
        cap->callback((const float*)pInput, (int)frameCount, cap->userdata);
        static int callCount = 0;
        if (++callCount == 1 || callCount == 100) {
            fprintf(stderr, "ma_helper: data_callback called (count=%d, frames=%u)\n", callCount, frameCount);
        }
    }
}

MaCapture* ma_capture_new(void) {
    return (MaCapture*)calloc(1, sizeof(MaCapture));
}

void ma_capture_free(MaCapture* cap) {
    if (!cap) return;
    if (cap->device_initialized) {
        ma_device_uninit(&cap->device);
    }
    if (cap->context_initialized) {
        ma_context_uninit(&cap->context);
    }
    free(cap);
}

/**
 * Find a capture device whose name contains the given substring.
 * Returns 0 on success, -1 on failure.
 */
static int find_device_by_name(ma_context* ctx, const char* name_substr, ma_device_id* out_id) {
    ma_device_info* capture_infos;
    ma_uint32 capture_count;

    if (ma_context_get_devices(ctx, NULL, NULL, &capture_infos, &capture_count) != MA_SUCCESS) {
        return -1;
    }

    for (ma_uint32 i = 0; i < capture_count; i++) {
        if (strstr(capture_infos[i].name, name_substr) != NULL) {
            *out_id = capture_infos[i].id;
            return 0;
        }
    }
    return -1;
}

/**
 * Initialize and start a capture device.
 *
 * device_name: NULL or "" for default device, or a substring to match against
 *              capture device names (e.g. "monitor" for PulseAudio/PipeWire loopback).
 *
 * Returns: 0 on success, negative on error:
 *   -1: context init failed
 *   -2: device not found by name
 *   -3: device init failed
 *   -4: device start failed
 */
int ma_capture_start(MaCapture* cap, const char* device_name,
                     int sample_rate, int channels,
                     MaSamplesCallback callback, void* userdata) {
    if (!cap) return -1;

    cap->callback = callback;
    cap->userdata = userdata;

    if (ma_context_init(NULL, 0, NULL, &cap->context) != MA_SUCCESS) {
        return -1;
    }
    cap->context_initialized = 1;

    /* Find device by name if specified */
    ma_device_id device_id;
    ma_device_id* p_device_id = NULL;

    if (device_name && device_name[0] != '\0') {
        if (find_device_by_name(&cap->context, device_name, &device_id) == 0) {
            p_device_id = &device_id;
        } else {
            return -2;
        }
    }

    ma_device_config config = ma_device_config_init(ma_device_type_capture);
    config.capture.pDeviceID = p_device_id;
    config.capture.format = ma_format_f32;
    config.capture.channels = (ma_uint32)channels;
    config.sampleRate = (ma_uint32)sample_rate;
    config.dataCallback = data_callback;
    config.pUserData = cap;

    ma_result initResult = ma_device_init(&cap->context, &config, &cap->device);
    if (initResult != MA_SUCCESS) {
        fprintf(stderr, "ma_helper: device init failed: %s\n", ma_result_description(initResult));
        return -3;
    }
    cap->device_initialized = 1;

    fprintf(stderr, "ma_helper: device '%s' initialized (backend=%s, format=%d, channels=%d, sampleRate=%d)\n",
            cap->device.capture.name,
            ma_get_backend_name(cap->context.backend),
            cap->device.capture.format,
            cap->device.capture.channels,
            cap->device.sampleRate);

    ma_result startResult = ma_device_start(&cap->device);
    if (startResult != MA_SUCCESS) {
        fprintf(stderr, "ma_helper: device start failed: %s\n", ma_result_description(startResult));
        return -4;
    }

    return 0;
}

void ma_capture_stop(MaCapture* cap) {
    if (!cap || !cap->device_initialized) return;
    ma_device_stop(&cap->device);
}

/**
 * Enumerate capture devices. Calls report() for each device found.
 * Returns number of devices, or -1 on error.
 */
int ma_enumerate_capture_devices(void (*report)(const char* name, void* userdata), void* userdata) {
    ma_context ctx;
    if (ma_context_init(NULL, 0, NULL, &ctx) != MA_SUCCESS) {
        return -1;
    }

    ma_device_info* capture_infos;
    ma_uint32 capture_count;

    if (ma_context_get_devices(&ctx, NULL, NULL, &capture_infos, &capture_count) != MA_SUCCESS) {
        ma_context_uninit(&ctx);
        return -1;
    }

    for (ma_uint32 i = 0; i < capture_count; i++) {
        report(capture_infos[i].name, userdata);
    }

    ma_context_uninit(&ctx);
    return (int)capture_count;
}

/**
 * Find the first monitor/loopback source name.
 * Copies the name into out_name (up to max_len chars).
 * Returns 0 on success, -1 if no monitor found.
 */
int ma_find_monitor_source(char* out_name, int max_len) {
    ma_context ctx;
    if (ma_context_init(NULL, 0, NULL, &ctx) != MA_SUCCESS) {
        return -1;
    }

    ma_device_info* capture_infos;
    ma_uint32 capture_count;

    if (ma_context_get_devices(&ctx, NULL, NULL, &capture_infos, &capture_count) != MA_SUCCESS) {
        ma_context_uninit(&ctx);
        return -1;
    }

    for (ma_uint32 i = 0; i < capture_count; i++) {
        if (strstr(capture_infos[i].name, "monitor") != NULL ||
            strstr(capture_infos[i].name, "Monitor") != NULL) {
            strncpy(out_name, capture_infos[i].name, (size_t)(max_len - 1));
            out_name[max_len - 1] = '\0';
            ma_context_uninit(&ctx);
            return 0;
        }
    }

    ma_context_uninit(&ctx);
    return -1;
}
