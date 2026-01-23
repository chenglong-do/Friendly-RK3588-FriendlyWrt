#!/bin/bash

sed -i -e '/CONFIG_MAKE_TOOLCHAIN=y/d' configs/rockchip/01-nanopi
sed -i -e 's/CONFIG_IB=y/# CONFIG_IB is not set/g' configs/rockchip/01-nanopi
sed -i -e 's/CONFIG_SDK=y/# CONFIG_SDK is not set/g' configs/rockchip/01-nanopi

echo "Replace Rust crates.io registry with mirror"
cat packages/rust/Makefile
sed -i 's/--set=llvm.download-ci-llvm=true/--set=source.crates-io.replace-with=mirror \
--set=source.mirror.registry=sparse+https:\/\/mirrors.bfsu.edu.cn\/crates.io-index\/ \
--set=llvm.download-ci-llvm=false/' packages/rust/Makefile
