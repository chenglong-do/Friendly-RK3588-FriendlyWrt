#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="25.12"
CPU="rk3588"
SET="non-docker"
MODE="all" # friendlywrt | image | all
WORKDIR="${REPO_ROOT}/local-build"
SKIP_INIT=0
SKIP_CUSTOM=0
SKIP_MAKE_DOWNLOAD=0
WITH_KERNEL_CONFIG=0
NO_RUST_PATCH=0
JOBS=""

usage() {
  cat <<'EOF'
Usage: scripts/local_build_ubuntu.sh [options]

Options:
  --version <ver>             FriendlyWrt version, default: 25.12
  --cpu <cpu>                 Target CPU, default: rk3588
  --set <set>                 Build set: non-docker|docker, default: non-docker
  --mode <mode>               Build mode: friendlywrt|image|all, default: all
  --workdir <dir>             Working directory, default: ./local-build
  --jobs <n>                  Parallel jobs for make, default: nproc
  --skip-init                 Skip environment initialization step
  --skip-custom               Skip custom scripts (add_packages/custome_config)
  --skip-make-download        Skip make download stage
  --with-kernel-config        Apply scripts/custome_kernel_config.sh during image build
  --no-rust-patch             Do not patch rust Makefile
  -h, --help                  Show this help message

Examples:
  scripts/local_build_ubuntu.sh --mode friendlywrt
  scripts/local_build_ubuntu.sh --mode all --version 25.12 --cpu rk3588
  scripts/local_build_ubuntu.sh --mode image --skip-init --workdir /data/fw-build
EOF
}

log() {
  echo "[$(date +'%F %T')] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

run_checked() {
  log "$*"
  "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="$2"
        shift 2
        ;;
      --cpu)
        CPU="$2"
        shift 2
        ;;
      --set)
        SET="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      --workdir)
        WORKDIR="$2"
        shift 2
        ;;
      --jobs)
        JOBS="$2"
        shift 2
        ;;
      --skip-init)
        SKIP_INIT=1
        shift
        ;;
      --skip-custom)
        SKIP_CUSTOM=1
        shift
        ;;
      --skip-make-download)
        SKIP_MAKE_DOWNLOAD=1
        shift
        ;;
      --with-kernel-config)
        WITH_KERNEL_CONFIG=1
        shift
        ;;
      --no-rust-patch)
        NO_RUST_PATCH=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  [[ "$MODE" =~ ^(friendlywrt|image|all)$ ]] || die "--mode must be friendlywrt|image|all"
  [[ "$SET" =~ ^(non-docker|docker)$ ]] || die "--set must be non-docker|docker"

  if [[ -z "$JOBS" ]]; then
    JOBS="$(nproc)"
  fi

  WORKDIR="$(mkdir -p "$WORKDIR" && cd "$WORKDIR" && pwd)"
}

prepare_host() {
  need_cmd git
  need_cmd wget
  need_cmd sudo
  need_cmd sed
  need_cmd tar

  if [[ "$SKIP_INIT" -eq 1 ]]; then
    log "skip host initialization"
    return
  fi

  local install_sh="${WORKDIR}/install.sh"
  run_checked sudo rm -rf /etc/apt/sources.list.d
  run_checked wget -O "$install_sh" https://raw.githubusercontent.com/friendlyarm/build-env-on-ubuntu-bionic/master/install.sh
  run_checked sed -i -e 's/^apt-get -y install openjdk-8-jdk/# apt-get -y install openjdk-8-jdk/g' "$install_sh"
  run_checked sed -i -e 's/^\[ -d fa-toolchain \]/# [ -d fa-toolchain ]/g' "$install_sh"
  run_checked sed -i -e 's/^(cat fa-toolchain/# (cat fa-toolchain/g' "$install_sh"
  run_checked sed -i -e 's/^(tar xf fa-toolchain/# (tar xf fa-toolchain/g' "$install_sh"
  run_checked sudo -E bash "$install_sh"

  run_checked git config --global user.name 'Local Build'
  run_checked git config --global user.email 'local@localhost'
  run_checked git config --global color.ui false

  if ! command -v repo >/dev/null 2>&1; then
    local repo_dir="${WORKDIR}/repo"
    run_checked git clone https://github.com/friendlyarm/repo "$repo_dir"
    run_checked sudo -E cp "$repo_dir/repo" /usr/bin/
  fi
}

download_friendly_source() {
  local project_dir="${WORKDIR}/project-friendlywrt"
  mkdir -p "$project_dir"
  pushd "$project_dir" >/dev/null

  if [[ ! -d .repo ]]; then
    run_checked repo init --depth=1 \
      -u https://github.com/friendlyarm/friendlywrt_manifests \
      -b "master-v${VERSION}" \
      -m rk3399.xml \
      --repo-url=https://github.com/friendlyarm/repo \
      --no-clone-bundle
  fi

  run_checked repo sync -c friendlywrt --no-clone-bundle
  run_checked repo sync -c configs --no-clone-bundle
  run_checked repo sync -c device/common --no-clone-bundle
  run_checked repo sync -c device/friendlyelec --no-clone-bundle
  run_checked repo sync -c scripts --no-clone-bundle
  run_checked repo sync -c scripts/sd-fuse --no-clone-bundle
  run_checked repo sync -c toolchain --no-clone-bundle

  popd >/dev/null
}

build_friendlywrt() {
  local project_dir="${WORKDIR}/project-friendlywrt"
  local artifact_dir="${WORKDIR}/artifact"
  local suffix=""
  local dist_dir config rootfs_filename host_pm_filename

  mkdir -p "$artifact_dir"
  [[ "$SET" == "docker" ]] && suffix="-docker"
  dist_dir="friendlywrt$(awk -F . '{print $1}' <<< "$VERSION")${suffix}"
  config="rockchip${suffix}"

  pushd "$project_dir" >/dev/null

  if [[ "$SKIP_CUSTOM" -eq 0 ]]; then
    # Run customization scripts in the same way as GitHub Actions.
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/add_packages.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/custome_config.sh"
  fi

  cat > .current_config.mk <<EOF
. device/friendlyelec/rk3399/base.mk
TARGET_IMAGE_DIRNAME=${dist_dir}
TARGET_FRIENDLYWRT_CONFIG=${config}
EOF

  run_checked env DEBUG_DOT_CONFIG=1 ./build.sh friendlywrt

  if [[ "$SKIP_MAKE_DOWNLOAD" -eq 0 ]]; then
    pushd friendlywrt >/dev/null
    run_checked make download -j8
    find dl -size -1024c -exec ls -l {} \;
    find dl -size -1024c -exec rm -f {} \;
    popd >/dev/null
  fi

  pushd friendlywrt >/dev/null
  if [[ "$NO_RUST_PATCH" -eq 0 ]] && [[ -f package/feeds/packages/rust/Makefile ]]; then
    run_checked sed -i 's/--set=llvm.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' package/feeds/packages/rust/Makefile
  fi

  if ! make -j"${JOBS}"; then
    log "parallel build failed, retrying with -j1 V=s"
    run_checked make -j1 V=s
  fi
  popd >/dev/null

  # shellcheck disable=SC1091
  source .current_config.mk
  rootfs_filename="rootfs-friendlywrt-${VERSION}${suffix}.tgz"
  host_pm_filename="host-pm-${VERSION}.tgz"

  run_checked tar czf "${artifact_dir}/${rootfs_filename}" \
    "${FRIENDLYWRT_SRC}/${FRIENDLYWRT_ROOTFS}" \
    "${FRIENDLYWRT_SRC}/${FRIENDLYWRT_PACKAGE_DIR}"

  if [[ "$SET" == "non-docker" ]]; then
    local pm_bin=""
    [[ -f ${FRIENDLYWRT_SRC}/staging_dir/host/bin/apk ]] && pm_bin="${FRIENDLYWRT_SRC}/staging_dir/host/bin/apk"
    [[ -f ${FRIENDLYWRT_SRC}/staging_dir/host/bin/opkg ]] && pm_bin="${FRIENDLYWRT_SRC}/staging_dir/host/bin/opkg"
    [[ -n "$pm_bin" ]] || die "neither apk nor opkg found under ${FRIENDLYWRT_SRC}/staging_dir/host/bin"
    run_checked tar czf "${artifact_dir}/${host_pm_filename}" "$pm_bin"
  fi

  popd >/dev/null
}

download_image_source() {
  local project_dir="${WORKDIR}/project-image"
  mkdir -p "$project_dir"
  pushd "$project_dir" >/dev/null

  if [[ ! -d .repo ]]; then
    run_checked repo init --depth=1 \
      -u https://github.com/friendlyarm/friendlywrt_manifests \
      -b "master-v${VERSION}" \
      -m "${CPU}.xml" \
      --repo-url=https://github.com/friendlyarm/repo \
      --no-clone-bundle
  fi

  run_checked repo sync -c kernel --no-clone-bundle
  run_checked repo sync -c u-boot --no-clone-bundle
  run_checked repo sync -c rkbin --no-clone-bundle
  run_checked repo sync -c configs --no-clone-bundle
  run_checked repo sync -c device/common --no-clone-bundle
  run_checked repo sync -c device/friendlyelec --no-clone-bundle
  run_checked repo sync -c scripts --no-clone-bundle
  run_checked repo sync -c scripts/sd-fuse --no-clone-bundle
  run_checked repo sync -c toolchain --no-clone-bundle

  popd >/dev/null
}

build_image() {
  local project_dir="${WORKDIR}/project-image"
  local artifact_dir="${WORKDIR}/artifact"
  local suffix=""
  local model img_file archive_file dist_dir config rootfs_file host_pm_file

  mkdir -p "$artifact_dir"
  [[ "$SET" == "docker" ]] && suffix="-docker"

  case "$CPU" in
    rk3588)
      model="T6-R6S-R6C-M6-Series"
      ;;
    *)
      die "unsupported cpu for local image build: $CPU"
      ;;
  esac

  img_file="${model}-FriendlyWrt-${VERSION}${suffix}.img"
  archive_file="images-${model}-FriendlyWrt-${VERSION}${suffix}.tgz"
  dist_dir="friendlywrt$(awk -F . '{print $1}' <<< "$VERSION")${suffix}"
  config="rockchip${suffix}"
  rootfs_file="${artifact_dir}/rootfs-friendlywrt-${VERSION}${suffix}.tgz"
  host_pm_file="${artifact_dir}/host-pm-${VERSION}.tgz"

  [[ -f "$rootfs_file" ]] || die "missing ${rootfs_file}, run --mode friendlywrt or --mode all first"
  if [[ "$SET" == "non-docker" ]]; then
    [[ -f "$host_pm_file" ]] || die "missing ${host_pm_file}, run --mode friendlywrt or --mode all first"
  fi

  pushd "$project_dir" >/dev/null

  cat > .current_config.mk <<EOF
. device/friendlyelec/${CPU}/base.mk
TARGET_IMAGE_DIRNAME=${dist_dir}
TARGET_FRIENDLYWRT_CONFIG=${config}
TARGET_SD_RAW_FILENAME=${img_file}
EOF

  run_checked tar xzf "$rootfs_file"
  if [[ "$SET" == "non-docker" ]]; then
    run_checked tar xzf "$host_pm_file"
  fi

  if [[ "$WITH_KERNEL_CONFIG" -eq 1 ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/custome_kernel_config.sh"
  fi

  run_checked ./build.sh uboot
  run_checked ./build.sh kernel
  run_checked ./build.sh sd-img

  run_checked mv "out/${img_file}" "${artifact_dir}/"

  pushd scripts/sd-fuse >/dev/null
  [[ -d "$dist_dir" ]] || die "image directory not found under scripts/sd-fuse/: ${dist_dir}"
  local archive_dir="${dist_dir}-${CPU}"
  run_checked mv "$dist_dir" "$archive_dir"
  run_checked tar czf "$archive_file" "$archive_dir"
  run_checked mv "$archive_file" "${artifact_dir}/"
  popd >/dev/null

  run_checked gzip -f "${artifact_dir}/${img_file}"

  popd >/dev/null
}

main() {
  parse_args "$@"

  [[ "$(uname -s)" == "Linux" ]] || die "this script is intended to run on Ubuntu/Linux"

  prepare_host

  case "$MODE" in
    friendlywrt)
      download_friendly_source
      build_friendlywrt
      ;;
    image)
      download_image_source
      build_image
      ;;
    all)
      download_friendly_source
      build_friendlywrt
      download_image_source
      build_image
      ;;
  esac

  log "build completed"
  log "artifact directory: ${WORKDIR}/artifact"
}

main "$@"

