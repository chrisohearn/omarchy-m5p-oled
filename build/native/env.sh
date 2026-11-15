# K114s native build environment (user-local tools only; nothing here touches the system).
# usage:  source ~/k114s-build/env.sh     (bash; safe to source more than once)
# Then use `kmake` (bin/kmake) instead of `make` in a kernel tree. See README-build.md.
export B="${K114S_BUILD_ROOT:-$HOME/k114s-build}"
export RUSTUP_HOME="$B/rustup" CARGO_HOME="$B/cargo" RUSTUP_TOOLCHAIN=1.98.1
export K114S_LLVM="$B/tools/llvm-23.1.3"          # official LLVM 23.1.3 Linux-ARM64 release
export K114S_ALARM="$B/tools/alarm/usr"           # bc, dtc, pahole (+ qemu if set up) from Arch Linux ARM packages
export K114S_BINDGEN="$B/tools/private-bindgen/bin/bindgen"   # bindgen 0.73.2 built by tools/aurora-bindgen/build.py
case ":$PATH:" in *":$B/bin:"*) ;; *)
  export PATH="$B/bin:$B/cargo/bin:$K114S_LLVM/bin:$K114S_ALARM/bin:/usr/local/bin:/usr/bin:/bin" ;;
esac
# pahole's libdwarves lives in the alarm prefix. The LLVM lib directory is deliberately NOT on
# LD_LIBRARY_PATH (it would shadow the system libLLVM for system programs); bindgen finds
# libclang through LIBCLANG_PATH.
case ":${LD_LIBRARY_PATH:-}:" in *":$K114S_ALARM/lib:"*) ;; *)
  export LD_LIBRARY_PATH="$K114S_ALARM/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac
export LIBCLANG_PATH="$K114S_LLVM/lib"
export ARCH=arm64 KBUILD_BUILD_HOST=archlinux KBUILD_BUILD_USER=linux-aurora
# The `uname -v` label is set by kmake at call time: KBUILD_BUILD_TIMESTAMP if you export it,
# else "$K114S_LABEL <date>" (export K114S_LABEL=K114S-R3-USB), else "K114S-DEV <date>".
# Default job count for kmake when the caller passes no -j (shared machine: 18 cores).
export K114S_JOBS="${K114S_JOBS:-10}"
