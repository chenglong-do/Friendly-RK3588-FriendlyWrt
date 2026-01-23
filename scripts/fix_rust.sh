#!/bin/bash
echo "Replace Rust crates.io registry with mirror"
find / -path "*/packages/rust/Makefile" 2>/dev/null
cat packages/rust/Makefile
sed -i 's/--set=llvm.download-ci-llvm=true/--set=source.crates-io.replace-with=mirror \
--set=source.mirror.registry=sparse+https:\/\/mirrors.bfsu.edu.cn\/crates.io-index\/ \
--set=llvm.download-ci-llvm=false/' packages/rust/Makefile