#!/bin/bash
# Script based partially on
# https://techviewleo.com/how-to-install-podman-on-ubuntu/
# https://podman.io/docs/installation#building-from-scratch
# https://github.com/containers/buildah/blob/main/install.md

#> aardvark-dns
#> buildah
#> catatonit
#> conmon
#> containernetworking-plugins
#> crun
#> fuse-overlayfs
# golang-github-containers-common
# golang-github-containers-image
#> netavark
#> passt
#> podman
#> slirp4netns

# sudo sysctl kernel.unprivileged_userns_clone=1
## to make it permanent
# echo 'kernel.unprivileged_userns_clone=1' > /etc/sysctl.d/userns.conf
#
# > zgrep CONFIG_USER_NS /proc/config.gz
# CONFIG_USER_NS=y

export PODMAN_WORKDIR=$HOME/oss/podman/
export PREFIX=${PREFIX:-${HOME}/env/}

[ -d "${PODMAN_WORKDIR}" ] || mkdir -p "${PODMAN_WORKDIR}"

opts=(${@:-all})

if [[ ! "${opts[*]}" =~ "nosudo" ]]; then
  echo "*** Installing dependencies ***"
  sudo apt install pkg-config cargo make curl gcc protobuf-compiler \
      vim git btrfs-progs iptables uidmap python3-pip \
      libassuan-dev libbtrfs-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libprotobuf-dev \
      libgpg-error-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config
fi

function get_latest_tag() {
  local github_project=$1
  local github_repo=$2
  local github_url=https://api.github.com/repos/$github_project/$github_repo/releases/latest
  local TAG=$(curl -s "${github_url}" | grep tag_name | cut -d '"' -f 4)
  echo $TAG
}

function get_repository() {
  local github_project=$1
  local github_repo=$2
  local tag=$3
  local repo_url="https://github.com/${github_project}/${github_repo}.git"
  # local repo_dir=$PODMAN_WORKDIR/${github_repo}-${tag}
  local repo_dir="${PODMAN_WORKDIR}/${github_repo}"

  if [[ ! -d ${repo_dir} ]]; then
    # git clone --depth 1 --recursive -b $tag https://github.com/$github_project/$github_repo.git $PODMAN_WORKDIR/${github_repo}-${tag}
    git clone --recursive --recurse-submodules -b "${tag}" "${repo_url}" "${repo_dir}" || exit 3
  fi

  if [[ -d "${repo_dir}" ]]; then
    pushd "${repo_dir}" >/dev/null || exit 5
    git fetch --tags >/dev/null
    git checkout -b "${tag}" "${tag}" >/dev/null
    git branch >/dev/null
    # git pull --recurse-submodules >/dev/null
    popd >/dev/null || exit 6
  fi

  if [[ ! -d ${repo_dir} ]]; then
    echo "Failed to get repo..."
    exit 2
  fi

  echo "${repo_dir}"
}

function prepare_pkg() {
  local github_project=$1
  local github_repo=$2
  local tag
  tag=$(get_latest_tag "${github_project}" "${github_repo}")
  local repo_dir
  repo_dir=$(get_repository "${github_project}" "${github_repo}" "${tag}")
  echo "${repo_dir}"
}

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "runc" ]]; then
  echo ""
  echo "*********** Installing runc ***********"
  echo "Project: https://github.com/opencontainers/runc"
  runc_workspace=$(prepare_pkg "opencontainers" "runc")
  echo "${runc_workspace}"
  pushd "${runc_workspace}" || exit 5
  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp"
  make -j $(( $(nproc --all) / 2 )) install
  popd || exit 6
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "crun" ]]; then
  echo ""
  echo "*********** Installing crun ***********"
  echo "Project: https://github.com/opencontainers/crun"
  crun_workspace=$(prepare_pkg "opencontainers" "crun")
  echo "${crun_workspace}"

  sudo apt-get install -y make git gcc build-essential pkgconf libtool \
      libsystemd-dev libprotobuf-c-dev libcap-dev libseccomp-dev libyajl-dev \
      libgcrypt20-dev go-md2man autoconf python3 automake

  pushd "${crun_workspace}" || exit 5
  ./autogen.sh
  ./configure --prefix=${PREFIX}
  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp"
  make -j $(( $(nproc --all) / 2 )) install
  popd || exit 7
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "conmon" ]]; then
  echo ""
  echo "*********** Installing conmon ***********"
  echo "Project: https://github.com/containers/conmon"
  conmon_workspace=$(prepare_pkg "containers" "conmon")
  pushd "${conmon_workspace}" || exit 5
  make -j $(( $(nproc --all) / 2 ))
  make -j $(( $(nproc --all) / 2 )) podman
  make -j $(( $(nproc --all) / 2 )) install
  # make -j8
  # make -j8 podman
  # make install
  popd || exit 8
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "plugins" ]]; then
  echo ""
  echo "*********** Installing network plugins ***********"
  echo "Project: https://github.com/containernetworking/plugins"
  plugins_workspace=$(prepare_pkg "containernetworking" "plugins")
  pushd "${plugins_workspace}" || exit 5
  ./build_linux.sh
  install -m 755 -d "${PREFIX}/libexec/cni/"
  cp ./bin/* "${PREFIX}/libexec/cni/"
  chmod o+rx "${PREFIX}"/libexec/cni/*
  popd || exit 9
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "buildah" ]]; then
  echo ""
  echo "*********** Installing buildah ***********"
  echo "Project: https://github.com/containers/buildah"
  buildah_workspace=$(prepare_pkg "containers" "buildah")
  echo "${buildah_workspace}"

  sudo apt-get -y -qq update
  sudo apt-get -y install bats btrfs-progs git go-md2man golang libapparmor-dev \
      libglib2.0-dev libgpgme11-dev libseccomp-dev libselinux1-dev make skopeo
  # containers-common

  pushd "${buildah_workspace}" || exit 5
  export GOPATH=`pwd`
  make PREFIX=${HOME}/env $(( $(nproc --all) / 2 )) runc all SECURITYTAGS="apparmor seccomp"
  make PREFIX=${HOME}/env $(( $(nproc --all) / 2 )) install install.runc
  make PREFIX=${HOME}/env $(( $(nproc --all) / 2 ))
  make PREFIX=${HOME}/env $(( $(nproc --all) / 2 )) install
  hash -r
  buildah --help

  popd || exit 10
fi

# https://github.com/containers/fuse-overlayfs.git
if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "fuse-overlayfs" ]]; then
  echo ""
  echo "*********** Installing fuse-overlayfs ***********"
  echo "Project: https://github.com/containers/fuse-overlayfs.git"
  fuse_overlayfs_workspace=$(prepare_pkg "containers" "fuse-overlayfs")
  echo "${fuse_overlayfs_workspace}"

  sudo apt install libfuse3-dev

  pushd "${fuse_overlayfs_workspace}" || exit 5
  ./autogen.sh
  ./configure --prefix=${HOME}/env
  make
  make install
  hash -r

  popd || exit 10
fi


# https://github.com/openSUSE/catatonit.git
if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "catatonit" ]]; then
  echo ""
  echo "*********** Installing catatonit ***********"
  echo "Project: https://github.com/openSUSE/catatonit.git"
  catatonit_workspace=$(prepare_pkg "openSUSE" "catatonit")
  echo "${catatonit_workspace}"

  pushd $catatonit_workspace
  ./autogen.sh
  ./configure --prefix=${HOME}/env
  make
  make install
  popd || exit 11
fi


# https://passt.top/passt
if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "passt" ]]; then
  echo ""
  echo "*********** Installing passt ***********"
  echo "Project: https://passt.top/passt"

  repo_url=https://passt.top/passt
  repo_dir=${PODMAN_WORKDIR}/passt
  tag=master

  if [[ ! -d ${repo_dir} ]]; then
    git clone --recursive --recurse-submodules -b "${tag}" "${repo_url}" "${repo_dir}" || exit 3
  fi

  if [[ -d "${repo_dir}" ]]; then
    pushd "${repo_dir}" >/dev/null || exit 5
    git fetch --tags >/dev/null
    git checkout -b "${tag}" "${tag}" >/dev/null
    git branch >/dev/null
    git pull --recurse-submodules >/dev/null
    popd >/dev/null || exit 6
  fi

  if [[ ! -d ${repo_dir} ]]; then
    echo "Failed to get repo..."
    exit 2
  fi

  pushd $repo_dir
  prefix=$HOME/env make
  prefix=$HOME/env make install
  popd || exit 11
fi


if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "aardvark-dns" ]]; then
  echo ""
  echo "*********** Installing aardvark-dns ***********"
  echo "Project: https://github.com/containers/aardvark-dns"
  aardvark_workspace=$(prepare_pkg "containers" "aardvark-dns")
  pushd "${aardvark_workspace}" || exit 5
  make -j $(( $(nproc --all) / 2 ))
  make -j $(( $(nproc --all) / 2 )) install
  popd || exit 11
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "netavark" ]]; then
  echo ""
  echo "*********** Installing netavark (DNS, etc.) ***********"
  echo "Project: https://github.com/containers/netavark"
  netavark_workspace=$(prepare_pkg "containers" "netavark")
  pushd "${netavark_workspace}" || exit 5
  make
  cp ./bin/* "${PREFIX}/bin/"
  chmod o+rx "${PREFIX}"/bin/netavark*
  popd || exit 12
fi

if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "podman" ]]; then
  echo ""
  echo "*********** Installing podman ***********"
  echo "Project: https://github.com/containers/podman"
  podman_workspace=$(prepare_pkg "containers" "podman")

  sudo apt install libsystemd-dev libsystemd-shared systemd-dev

  pushd "${podman_workspace}" || exit 5

  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp"
  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp" PREFIX=${HOME}/env/ binaries
  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp" PREFIX=${HOME}/env/ install
  make -j $(( $(nproc --all) / 2 )) BUILDTAGS="selinux seccomp" PREFIX=${HOME}/env/ install.tools

  popd || exit 13
fi

if [[ ! "${opts[*]}" =~ "nosudo" ]]; then
if [[ "${opts}" == "all" ]] || [[ ${opts[*]} =~ "containers" ]]; then
  sudo mkdir -p /etc/containers
  sudo chmod 755 /etc/containers
  # sudo curl -L -o /etc/containers/registries.conf https://src.fedoraproject.org/rpms/containers-common/raw/main/f/registries.conf

  sudo cat <<EOF > /etc/containers/registries.conf
# For more information on this configuration file, see containers-registries.conf(5).
#
# NOTE: RISK OF USING UNQUALIFIED IMAGE NAMES
# We recommend always using fully qualified image names including the registry
# server (full dns name), namespace, image name, and tag
# (e.g., registry.redhat.io/ubi8/ubi:latest). Pulling by digest (i.e.,
# quay.io/repository/name@digest) further eliminates the ambiguity of tags.
# When using short names, there is always an inherent risk that the image being
# pulled could be spoofed. For example, a user wants to pull an image named
# `foobar` from a registry and expects it to come from myregistry.com. If
# myregistry.com is not first in the search list, an attacker could place a
# different `foobar` image at a registry earlier in the search list. The user
# would accidentally pull and run the attacker's image and code rather than the
# intended content. We recommend only adding registries which are completely
# trusted (i.e., registries which don't allow unknown or anonymous users to
# create accounts with arbitrary names). This will prevent an image from being
# spoofed, squatted or otherwise made insecure.  If it is necessary to use one
# of these registries, it should be added at the end of the list.
#
# # An array of host[:port] registries to try when pulling an unqualified image, in order.
unqualified-search-registries = ["registry.fedoraproject.org", "registry.access.redhat.com", "registry.centos.org", "docker.io", "quay.io"]
#
# [[registry]]

[[registry]]
location="localhost:5000"
insecure=true

# # The "prefix" field is used to choose the relevant [[registry]] TOML table;
# # (only) the TOML table with the longest match for the input image name
# # (taking into account namespace/repo/tag/digest separators) is used.
# #
# # The prefix can also be of the form: *.example.com for wildcard subdomain
# # matching.
# #
# # If the prefix field is missing, it defaults to be the same as the "location" field.
# prefix = "example.com/foo"
#
# # If true, unencrypted HTTP as well as TLS connections with untrusted
# # certificates are allowed.
# insecure = false
#
# # If true, pulling images with matching names is forbidden.
# blocked = false
#
# # The physical location of the "prefix"-rooted namespace.
# #
# # By default, this is equal to "prefix" (in which case "prefix" can be omitted
# # and the [[registry]] TOML table can only specify "location").
# #
# # Example: Given
# #   prefix = "example.com/foo"
# #   location = "internal-registry-for-example.net/bar"
# # requests for the image example.com/foo/myimage:latest will actually work with the
# # internal-registry-for-example.net/bar/myimage:latest image.
#
# # The location can be empty iff prefix is in a
# # wildcarded format: "*.example.com". In this case, the input reference will
# # be used as-is without any rewrite.
# location = internal-registry-for-example.com/bar"
#
# # (Possibly-partial) mirrors for the "prefix"-rooted namespace.
# #
# # The mirrors are attempted in the specified order; the first one that can be
# # contacted and contains the image will be used (and if none of the mirrors contains the image,
# # the primary location specified by the "registry.location" field, or using the unmodified
# # user-specified reference, is tried last).
# #
# # Each TOML table in the "mirror" array can contain the following fields, with the same semantics
# # as if specified in the [[registry]] TOML table directly:
# # - location
# # - insecure
# [[registry.mirror]]
# location = "example-mirror-0.local/mirror-for-foo"
# [[registry.mirror]]
# location = "example-mirror-1.local/mirrors/foo"
# insecure = true
# # Given the above, a pull of example.com/foo/image:latest will try:
# # 1. example-mirror-0.local/mirror-for-foo/image:latest
# # 2. example-mirror-1.local/mirrors/foo/image:latest
# # 3. internal-registry-for-example.net/bar/image:latest
# # in order, and use the first one that exists.
short-name-mode = "permissive"
EOF

  # sudo curl -L -o /etc/containers/policy.json https://src.fedoraproject.org/rpms/containers-common/raw/main/f/default-policy.json

  sudo cat <<EOF > /etc/containers/policy.json
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports":
        {
            "docker-daemon":
                {
                    "": [{"type":"insecureAcceptAnything"}]
                }
        }
}
EOF

  echo ""
  echo "*** Setup uid/gid ***"
  sudo usermod --add-subgids 2000-75535 "${USER}"
  sudo usermod --add-subuids 2000-75535 "${USER}"

  if [[ ! -f "/etc/containers/containers.conf" ]]; then
    echo ""
    echo "Enable netavark by default"
    sudo cat <<EOF > /etc/containers/containers.conf
[network]

# Explicitly force "netavark" as to not use the outdated CNI networking, which it would not apply otherwise as long as old stuff is there.
# This may be removed once all containers were upgraded?
# see https://discussion.fedoraproject.org/t/how-to-get-podman-dns-plugin-container-name-resolution-to-work-in-fedora-coreos-36-podman-plugins-podman-dnsname/39493/5?u=rugk

# official doc:
# Network backend determines what network driver will be used to set up and tear down container networks.
# Valid values are "cni" and "netavark".
# The default value is empty which means that it will automatically choose CNI or netavark. If there are
# already containers/images or CNI networks preset it will choose CNI.
#
# Before changing this value all containers must be stopped otherwise it is likely that
# iptables rules and network interfaces might leak on the host. A reboot will fix this.

network_backend = "netavark"

# Path to directory where CNI plugin binaries are located.
cni_plugin_dirs = ["/usr/libexec/cni", "/home/amitkr/my/env/libexec/podman", "/home/amitkr/my/env/libexec/cni"]

# The network name of the default CNI network to attach pods to.
# default_network = "podman"

# Path to the directory where CNI configuration files are located.
#
# network_config_dir = "/etc/cni/net.d/"

[engine]
helper_binaries_dir = ["/home/amitkr/my/env/bin", "/home/amitkr/my/env/libexec", "/home/amitkr/my/env/libexec/podman", "/home/amitkr/my/env/libexec/cni"]
EOF
  else
    echo "/etc/containers/containers.conf already exists, we won't touch it"
  fi

  sudo chmod 644 /etc/containers/containers.conf
  sudo chmod 644 /etc/containers/registries.conf
  sudo chmod 644 /etc/containers/policy.json

  podman system migrate

  echo ""
  echo "*** Installing podman-compose ***"
  # python3 -m pip install --user podman-compose
  pipx install podman-compose
fi
fi

echo ""
