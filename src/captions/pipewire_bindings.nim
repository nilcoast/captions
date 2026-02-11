## Hand-written libpipewire-0.3 C interop bindings.
## Only the subset needed for audio stream capture.

{.passl: gorge("pkg-config --libs libpipewire-0.3").}
{.passc: gorge("pkg-config --cflags libpipewire-0.3").}

type
  PwMainLoop* {.importc: "struct pw_main_loop", header: "<pipewire/pipewire.h>", incompleteStruct.} = object
  PwMainLoopPtr* = ptr PwMainLoop

  PwLoop* {.importc: "struct pw_loop", header: "<pipewire/pipewire.h>", incompleteStruct.} = object
  PwLoopPtr* = ptr PwLoop

  PwStream* {.importc: "struct pw_stream", header: "<pipewire/pipewire.h>", incompleteStruct.} = object
  PwStreamPtr* = ptr PwStream

  PwProperties* {.importc: "struct pw_properties", header: "<pipewire/pipewire.h>", incompleteStruct.} = object
  PwPropertiesPtr* = ptr PwProperties

  SpaBuffer* {.importc: "struct spa_buffer", header: "<spa/buffer/buffer.h>".} = object
    n_metas*: uint32
    n_datas*: uint32
    metas*: pointer           # struct spa_meta*
    datas*: ptr UncheckedArray[SpaData]
  SpaBufferPtr* = ptr SpaBuffer

  PwBuffer* {.importc: "struct pw_buffer", header: "<pipewire/stream.h>".} = object
    buffer*: SpaBufferPtr
    user_data*: pointer
    size*: uint64
  PwBufferPtr* = ptr PwBuffer

  SpaPod* {.importc: "struct spa_pod", header: "<spa/pod/pod.h>", incompleteStruct.} = object
  SpaPodPtr* = ptr SpaPod

  SpaData* {.importc: "struct spa_data", header: "<spa/buffer/buffer.h>".} = object
    `type`* {.importc: "type".}: uint32
    flags*: uint32
    fd*: int64
    mapoffset*: uint32
    maxsize*: uint32
    data*: pointer
    chunk*: ptr SpaChunk

  SpaChunk* {.importc: "struct spa_chunk", header: "<spa/buffer/buffer.h>".} = object
    offset*: uint32
    size*: uint32
    stride*: int32
    flags*: int32

  PwStreamEvents* {.importc: "struct pw_stream_events", header: "<pipewire/stream.h>".} = object
    version*: uint32
    destroy*: pointer
    state_changed*: pointer
    control_info*: pointer
    io_changed*: pointer
    param_changed*: pointer
    add_buffer*: pointer
    remove_buffer*: pointer
    process*: proc (userdata: pointer) {.cdecl.}
    drained*: pointer
    command*: pointer
    trigger_done*: pointer

  PwDirection* {.size: sizeof(cint).} = enum
    PW_DIRECTION_INPUT = 0
    PW_DIRECTION_OUTPUT = 1

  PwStreamFlags* = distinct uint32

  PwStreamState* {.size: sizeof(cint).} = enum
    PW_STREAM_STATE_ERROR = -1
    PW_STREAM_STATE_UNCONNECTED = 0
    PW_STREAM_STATE_CONNECTING = 1
    PW_STREAM_STATE_PAUSED = 2
    PW_STREAM_STATE_STREAMING = 3

const
  PW_STREAM_FLAG_AUTOCONNECT* = PwStreamFlags(1 shl 0)
  PW_STREAM_FLAG_INACTIVE* = PwStreamFlags(1 shl 1)
  PW_STREAM_FLAG_MAP_BUFFERS* = PwStreamFlags(1 shl 2)
  PW_STREAM_FLAG_DRIVER* = PwStreamFlags(1 shl 3)
  PW_STREAM_FLAG_RT_PROCESS* = PwStreamFlags(1 shl 4)
  PW_STREAM_EVENTS_VERSION*: uint32 = 2

  PW_KEY_MEDIA_TYPE* = "media.type"
  PW_KEY_MEDIA_CATEGORY* = "media.category"
  PW_KEY_MEDIA_ROLE* = "media.role"
  PW_KEY_STREAM_CAPTURE_SINK* = "stream.capture.sink"
  PW_KEY_NODE_NAME* = "node.name"

proc `or`*(a, b: PwStreamFlags): PwStreamFlags =
  PwStreamFlags(a.uint32 or b.uint32)

# --- Core PipeWire functions ---

proc pw_init*(argc: ptr cint, argv: ptr cstringArray) {.importc, header: "<pipewire/pipewire.h>".}
proc pw_deinit*() {.importc, header: "<pipewire/pipewire.h>".}

type
  SpaDict* {.importc: "struct spa_dict", header: "<spa/utils/dict.h>", incompleteStruct.} = object
  SpaDictPtr* = ptr SpaDict

proc pw_main_loop_new*(props: SpaDictPtr): PwMainLoopPtr {.importc, header: "<pipewire/main-loop.h>".}
proc pw_main_loop_destroy*(loop: PwMainLoopPtr) {.importc, header: "<pipewire/main-loop.h>".}
proc pw_main_loop_run*(loop: PwMainLoopPtr): cint {.importc, header: "<pipewire/main-loop.h>".}
proc pw_main_loop_quit*(loop: PwMainLoopPtr): cint {.importc, header: "<pipewire/main-loop.h>".}
proc pw_main_loop_get_loop*(loop: PwMainLoopPtr): PwLoopPtr {.importc, header: "<pipewire/main-loop.h>".}

proc pw_properties_new*(key1: cstring): PwPropertiesPtr {.importc, header: "<pipewire/properties.h>", varargs.}

proc pw_stream_new_simple*(
  loop: PwLoopPtr,
  name: cstring,
  props: PwPropertiesPtr,
  events: ptr PwStreamEvents,
  userdata: pointer
): PwStreamPtr {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_destroy*(stream: PwStreamPtr) {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_connect*(
  stream: PwStreamPtr,
  direction: PwDirection,
  target_id: uint32,
  flags: PwStreamFlags,
  params: pointer,  # const struct spa_pod **
  n_params: uint32
): cint {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_disconnect*(stream: PwStreamPtr): cint {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_dequeue_buffer*(stream: PwStreamPtr): PwBufferPtr {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_queue_buffer*(stream: PwStreamPtr, buffer: PwBufferPtr): cint {.importc, header: "<pipewire/stream.h>".}

proc pw_stream_get_state*(stream: PwStreamPtr, error: ptr cstring): PwStreamState {.importc, header: "<pipewire/stream.h>".}

const PW_ID_ANY*: uint32 = 0xffffffff'u32

# --- Access pw_buffer internals ---
# Now using proper importc structs — no manual pointer math needed.

# --- SPA format pod builder (from C helper) ---

{.compile: "spa_helper.c".}

proc build_audio_format_pod*(
  buffer: ptr uint8,
  buffer_size: csize_t,
  sample_rate: uint32,
  channels: uint32
): SpaPodPtr {.importc, cdecl.}
