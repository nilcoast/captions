/**
 * Small C helper for building SPA format pods.
 * SPA uses complex macros that can't be imported into Nim directly.
 */

#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

/**
 * Build an SPA audio format pod for F32 mono/stereo at the given sample rate.
 * Returns a pointer to the built pod (inside the provided buffer).
 */
const struct spa_pod *build_audio_format_pod(
    uint8_t *buffer,
    size_t buffer_size,
    uint32_t sample_rate,
    uint32_t channels)
{
    struct spa_pod_builder b;
    spa_pod_builder_init(&b, buffer, buffer_size);

    struct spa_audio_info_raw info = SPA_AUDIO_INFO_RAW_INIT(
        .format = SPA_AUDIO_FORMAT_F32,
        .rate = sample_rate,
        .channels = channels);

    return spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);
}
