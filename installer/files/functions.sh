#/bin/bash

function create_mock_config(){
    CHROOT="${1:-messaging10s-rabbitmq}"
    REPO_NAME="$(echo -e $CHROOT | cut -d- -f2)-deps"
    REPO_PATH="${HOME}/data/repos/${REPO_NAME}"
    MOCK_CONFIG_FILE="${HOME}/workspace/${CHROOT}-x86_64.cfg"
    mkdir $REPO_PATH >/dev/null 2>&1
    cp /etc/mock/centos-stream-10-x86_64.cfg $MOCK_CONFIG_FILE
    sed -i "s/config_opts\['root'\].*/config_opts['root'] = '${CHROOT}-x86_64'/" ${MOCK_CONFIG_FILE}
    cat <<EOF >> ${MOCK_CONFIG_FILE}
config_opts['dnf.conf'] += """
[${CHROOT}]
name=$CHROOT
baseurl=file://$REPO_PATH
enabled=1
gpgcheck=0
"""
EOF
    createrepo $REPO_PATH
    echo -e "The mock configuratin file is created $MOCK_CONFIG_FILE"
}

function prepare_rpm_topdir(){
    pkg_dir="$1"
    dist="${2:-el9s}"
    if [ ! -n "$pkg_dir" ]; then
        echo -e "Error: needs path as argument"
        return 1
    fi
    is_spec_dir=$(find $pkg_dir -maxdepth 1 -name SPECS -type d)
    if [ -n "$is_spec_dir" ]; then
        top_dir="${pkg_dir}"
        mkdir -p ${top_dir}/{BUILD,BUILDROOT} >/dev/null 2>&1
        rpm_dir="${pkg_dir}"
        srpm_dir="${pkg_dir}"
        source_dir="${top_dir}/SOURCES"
        spec_dir="${top_dir}/SPECS"
        build_dir="${top_dir}/BUILD"
        buildroot_dir="${top_dir}/BUILDROOT"
    else
        top_dir="${pkg_dir}/rpmbuild"
        mkdir -p ${top_dir}/{BUILD,BUILDROOT} >/dev/null 2>&1
        rpm_dir="${pkg_dir}"
        srpm_dir="${pkg_dir}"
        source_dir="${pkg_dir}"
        spec_dir="${pkg_dir}"
        build_dir="${top_dir}/BUILD"
        buildroot_dir="${top_dir}/BUILDROOT"
    fi
}

function build_srpm(){
    VERBOSE_LEVEL='0'
    pkg_dir="${1:-$PWD}"
    dist=.el10s

    prepare_rpm_topdir $pkg_dir $dist
    # Download remote sources (only) with debug enabled
    download_sources=$(spectool -g -S -D -C $source_dir $spec_dir/*.spec 2>/dev/null)
    print_out 1 $download_sources
    print_out 0 "Build SRPM init \tOK"
    
    rpmbuild -bs --define="_rpmdir ${rpm_dir}" --define="_srcrpmdir ${srpm_dir}" --define="_sourcedir ${source_dir}" --define="_specdir ${spec_dir}" --define="_builddir ${build_dir}" --define="dist ${dist}" --buildroot='${buildroot_dir}' ${spec_dir}/*.spec
    srpm_filename=$(find $srpm_dir -name *.src.rpm -printf "%f")
    if [ -n "$srpm_filename" ]; then
        print_out 0 "Build SRPM \t\tOK => $srpm_filename"
    else
        print_out 0 "Error while building SRPM"
        return 1
    fi
}

function mock_build {
    mock_config_path="$1"
    srpm_file="$2"
    ts=$(date +"%Y-%m-%d-%H-%M-%S")
    if [ ! -n "$srpm_file" ]; then
        srpm_file=$(find $PWD -maxdepth 1 -name *.src.rpm -type f)
    fi
    if [ ! -n "$mock_config_path" ] || [ ! -n "$mock_config_path" ]; then
        echo -e "Error: needs mock_config_path and SRPM as arguments"
        return 1
    fi
    mock -r $mock_config_path $srpm_file
    RET_CODE=$?
    build_dir=$(find $PWD -maxdepth 2 -name BUILD -type d)
    mkdir $build_dir/$ts
    rm current >/dev/null 2>&1
    ln -s $build_dir/$ts $build_dir/current
    mock_config=$(basename $mock_config_path)
    cp /var/lib/mock/${mock_config%.*}/result/* $build_dir/current/
    if [ $RET_CODE -eq 0 ]; then
        print_out 0 "Local build \t\t[SUCCESS]"
    elif [ $RET_CODE -eq 1 ]; then
        print_out 0 "Local build \t\t[ERROR] \nSee details in $build_dir/current"
        return 1
    else
        print_out 0 "Local build \t\t[ERROR] \nSee details in $build_dir/current"
        return 4
    fi
}

function build {
    mock_config="$1"
    mock_config_path="${HOME}/workspace/${mock_config}-x86_64.cfg"
    repo_name="$(echo -e $mock_config | cut -d- -f2)-deps"
    repo_path="${HOME}/data/repos/${repo_name}"
    create_mock_config $mock_config
    build_srpm
    mock_build $mock_config_path
    if [[ $? -eq 0 ]]; then
        cp *.rpm $repo_path
	createrepo $repo_path
    fi
}
function print_out {
    local THIS_LEVEL=$1
    shift
    local MESSAGE="${@}"
    if [[ "${THIS_LEVEL}" -le "${VERBOSE_LEVEL}" ]]; then
       printf "${MESSAGE}\n"
    fi
}
