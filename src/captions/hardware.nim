## Hardware detection for model tier recommendation.
## Detects GPU, VRAM, and total system RAM on macOS and Linux.

import std/[os, strutils, logging, osproc]

type
  GpuInfo* = object
    name*: string
    vramMb*: int
    hasGpu*: bool

  HardwareInfo* = object
    totalRamMb*: int
    gpu*: GpuInfo

  ModelTier* = enum
    mt7B = "7B"
    mt14B = "14B"
    mt32B = "32B"

when defined(macosx):
  # macOS: Use sysctl for RAM, Metal for GPU info
  proc sysctlbyname(name: cstring, oldp: pointer, oldlenp: ptr csize_t,
                     newp: pointer, newlen: csize_t): cint
    {.importc, header: "<sys/sysctl.h>".}

  proc detectHardware*(): HardwareInfo =
    # Total RAM via sysctl
    var memsize: uint64
    var size = csize_t(sizeof(memsize))
    if sysctlbyname("hw.memsize", addr memsize, addr size, nil, 0) == 0:
      result.totalRamMb = int(memsize div (1024 * 1024))

    # On Apple Silicon, GPU memory is unified with system RAM.
    # Use IOKit to check for Apple GPU.
    let (gpuOutput, gpuRc) = execCmdEx(
      "system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal'"
    )
    if gpuRc == 0 and gpuOutput.len > 0:
      result.gpu.hasGpu = true
      for line in gpuOutput.splitLines():
        let trimmed = line.strip()
        if trimmed.startsWith("Chipset Model:"):
          result.gpu.name = trimmed.split(":")[1].strip()
        elif trimmed.startsWith("VRAM"):
          # e.g. "VRAM (Total):  16 GB" or "VRAM (Dynamic, Max): 48 GB"
          let parts = trimmed.split(":")
          if parts.len > 1:
            let valStr = parts[1].strip().split(" ")[0]
            try:
              let gb = parseInt(valStr)
              result.gpu.vramMb = gb * 1024
            except ValueError:
              discard

      # Apple Silicon unified memory — GPU can use most of system RAM
      if result.gpu.vramMb == 0 and result.gpu.name.toLowerAscii().contains("apple"):
        result.gpu.vramMb = result.totalRamMb

else:
  # Linux: Parse /proc/meminfo for RAM, sysfs/nvidia-smi for GPU
  proc detectHardware*(): HardwareInfo =
    # Total RAM
    if fileExists("/proc/meminfo"):
      for line in lines("/proc/meminfo"):
        if line.startsWith("MemTotal:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            try:
              result.totalRamMb = parseInt(parts[1]) div 1024
            except ValueError:
              discard
          break

    # GPU detection: try AMD sysfs first, then NVIDIA
    # AMD: /sys/class/drm/card*/device/mem_info_vram_total
    var foundGpu = false
    for kind, path in walkDir("/sys/class/drm"):
      if kind == pcDir and path.extractFilename().startsWith("card"):
        let vramFile = path / "device" / "mem_info_vram_total"
        if fileExists(vramFile):
          try:
            let vramBytes = parseBiggestUInt(readFile(vramFile).strip())
            result.gpu.vramMb = int(vramBytes div (1024 * 1024))
            result.gpu.hasGpu = true
            foundGpu = true
            # Try to get GPU name
            let nameFile = path / "device" / "product_name"
            if fileExists(nameFile):
              result.gpu.name = readFile(nameFile).strip()
            elif fileExists(path / "device" / "vendor"):
              result.gpu.name = "AMD GPU"
            break
          except CatchableError:
            discard

    # NVIDIA: nvidia-smi
    if not foundGpu:
      let (nvOutput, nvRc) = execCmdEx(
        "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null"
      )
      if nvRc == 0 and nvOutput.strip().len > 0:
        let parts = nvOutput.strip().split(",")
        if parts.len >= 2:
          result.gpu.hasGpu = true
          result.gpu.name = parts[0].strip()
          try:
            result.gpu.vramMb = parseInt(parts[1].strip())
          except ValueError:
            discard

proc availableMemoryMb*(hw: HardwareInfo): int =
  ## Estimate available memory for model loading.
  ## Uses VRAM if GPU present, otherwise system RAM.
  if hw.gpu.hasGpu and hw.gpu.vramMb > 0:
    hw.gpu.vramMb
  else:
    hw.totalRamMb

proc recommendTier*(hw: HardwareInfo): ModelTier =
  ## Recommend a model tier based on available memory.
  let memMb = availableMemoryMb(hw)
  if memMb > 40 * 1024:
    mt32B
  elif memMb >= 18 * 1024:
    mt14B
  else:
    mt7B

proc tierDescription*(tier: ModelTier): string =
  case tier
  of mt7B: "Qwen2.5 7B (Q4_K_M) - ~4.4 GB, fast inference"
  of mt14B: "Qwen2.5 14B (Q4_K_M) - ~8.3 GB, balanced"
  of mt32B: "Qwen2.5 32B (Q4_K_M) - ~18.9 GB, highest quality"
