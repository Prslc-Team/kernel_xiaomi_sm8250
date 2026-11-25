#!/bin/bash

# This build script references and adapts logic from:
# - [scripts/build_kernel] by UtsavBalar1231
# - [build.sh] by liyafe1997
# - [.github/workflows/Build_Kernel.yml] by yspbwx2010
# Many thanks to their authors for the inspiration.

set -e

TOOLCHAIN_PATH=$HOME/toolchain/kernel_build/google-clang/bin
GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)
TARGET_DEVICE=$1

if [ -z "$1" ]; then
    echo "Error: No argument provided. Check the README (Build section)."
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    echo "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] does not exist."
    echo "Please ensure the toolchain is there, or change TOOLCHAIN_PATH in the script to your toolchain path."
    exit 1
fi

echo "TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

for cmd in aarch64-linux-gnu-ld arm-linux-gnueabi-ld clang; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "[$cmd] does not exist, please check your environment."
        exit 1
    fi
done

# Enable ccache for speed up compiling 
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CC="ccache gcc"
export CXX="ccache g++"
export PATH="/usr/lib/ccache:$PATH"
echo "CCACHE_DIR: [$CCACHE_DIR]"

MAKE_ARGS="ARCH=arm64 \
    SUBARCH=arm64 \
    O=out \
    CC=clang \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    CLANG_TRIPLE=aarch64-linux-gnu-"

if [ "$1" == "j1" ]; then
    make $MAKE_ARGS -j1
    exit
fi

if [ "$1" == "continue" ]; then
    make $MAKE_ARGS -j$(nproc)
    exit
fi

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    echo "No target device [${TARGET_DEVICE}] found."
    echo "Available defconfigs, please choose one target from below:"
    ls arch/arm64/configs/*_defconfig
    exit 1
fi

echo "[clang --version]:"
clang --version

TARGET_SYSTEM=$2

if [ -n "$TARGET_SYSTEM" ] && [ "$TARGET_SYSTEM" != "aosp" ] && [ "$TARGET_SYSTEM" != "miui" ]; then
    echo "Error: Unknown target system [$TARGET_SYSTEM]. Expected: aosp or miui."
    exit 1
fi

echo "TARGET_DEVICE: $TARGET_DEVICE"

echo "Cleaning..."
rm -rf out/
rm -rf anykernel/

echo "Clone AnyKernel3 for packing kernel (repo: https://github.com/liyafe1997/AnyKernel3)"
git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel

Build_AOSP() {
    echo "Building for AOSP......"
    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
    SET_CONFIG
    make $MAKE_ARGS -j$(nproc)
    Image_Repack
    echo "Build for AOSP finished."
}

Build_MIUI(){
    echo "Clearning [out/] and build for MIUI....."
    rm -rf out/

    dts_source=arch/arm64/boot/dts/vendor/qcom

    # Backup dts (drop any stale backup left behind by an aborted run)
    rm -rf .dts.bak
    cp -a ${dts_source} .dts.bak
    # Restore the original dts even if the build aborts midway
    trap 'rm -rf ${dts_source}; mv .dts.bak ${dts_source}' EXIT

    # Correct panel dimensions on MIUI builds
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j2*
    sed -i 's/<155>/<1544>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<155>/<1545>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j2*

    # Enable back mi smartfps while disabling qsync min refresh-rate
    sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${dts_source}/dsi-panel*

    # Enable back refresh rates supported on MIUI
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
    sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi

    # Enable back brightness control from dtsi
    sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi

    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig

    SET_CONFIG MIUI

    make $MAKE_ARGS -j$(nproc)

    Image_Repack MIUI
}

SET_CONFIG() {
    if [ "$1" == "MIUI" ]; then
        scripts/config --file out/.config \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK \
            -e SF_BINDER \
            -e OVERLAY_FS \
            -d DEBUG_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e MILLET \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -d LOCALVERSION_AUTO \
            -e SF_BINDER \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -d MODULE_SIG_SHA512 \
            -d MODULE_SIG_HASH \
            -e MI_FRAGMENTION \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM
    fi
}

Image_Repack() {
    if [ -f "out/arch/arm64/boot/Image" ]; then
        echo "The file [out/arch/arm64/boot/Image] exists. Build successfully."
    else
        echo "The file [out/arch/arm64/boot/Image] does not exist. Seems build failed."
        exit 1
    fi

    echo "Generating [out/arch/arm64/boot/dtb]......"
    find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb

    # Restore modified dts
    if [ "$1" == "MIUI" ]; then
        rm -rf ${dts_source}
        mv .dts.bak ${dts_source}
        trap - EXIT
    fi

    rm -rf anykernel/kernels/
    mkdir -p anykernel/kernels/
    cp out/arch/arm64/boot/Image anykernel/kernels/
    cp out/arch/arm64/boot/dtb anykernel/kernels/
    cd anykernel

    if [ "$1" == "MIUI" ]; then
        ZIP_FILENAME=Kernel_MIUI_${TARGET_DEVICE}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip
    else
        ZIP_FILENAME=Kernel_AOSP_${TARGET_DEVICE}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip
    fi

    zip -r9 $ZIP_FILENAME ./* -x .git .gitignore out/ ./*.zip
    mv $ZIP_FILENAME ../
    cd ..
    echo "Done. The flashable zip is: [./$ZIP_FILENAME]"
}

if [ "$TARGET_SYSTEM" == "aosp" ]; then
    Build_AOSP
elif [ "$TARGET_SYSTEM" == "miui" ]; then
    Build_MIUI
else
    Build_AOSP
    Build_MIUI
fi
