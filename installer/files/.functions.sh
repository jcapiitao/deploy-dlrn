#/bin/bash

function prepare_mock_build(){
    local target="${1:-messaging-rabbitmq}"
    repo_path="${HOME}/data/repos/$target"
    mock_config_file="${HOME}/workspace/$target/$target-x86_64.cfg"
}

function add_repo_readme(){
    local repo_path=${1:-$repo_path}
    cat <<EOF >> $repo_path/_README.txt
- build_order.log file contains the order in which the SRPMS/RPMs were built
- *.buildinfo files contain the distgit URL and the branch from which the SRPMS/RPMS were built
- *.patch files contain the local changes needed to build. If there is not .patch file for a SRPM, then it was built from the branch without local changes.
EOF
}

function create_mock_config(){
    target="${1:-messaging-rabbitmq}"
    prepare_mock_build $target
    mkdir -p $repo_path >/dev/null 2>&1
    add_repo_readme
    cp /etc/mock/centos-stream-10-x86_64.cfg $mock_config_file
    sed -i "s/config_opts\['root'\].*/config_opts['root'] = '$target-x86_64'/" $mock_config_file
    sed -i "1s/^/config_opts['dist'] = 'el10s'\n/" $mock_config_file
    cat <<EOF >> $mock_config_file
config_opts['dnf.conf'] += """
[${target}]
name=$target
baseurl=file://$repo_path
enabled=1
gpgcheck=0
"""
EOF
    [ "$(ls -A $repo_path/repodata)" ] || create_repo $repo_path
    print_out 0 "Mock conf file \t\tOK => $mock_config_file"
}

function create_repo(){
    repo_path=$1
    result=$(createrepo $repo_path)
    if [[ $? -eq 0 ]]; then
        print_out 0 "Repo generation \tOK => $repo_path"
    else
        print_out 0 "Repo generation \tNOT OK"
        print_out 0 "$result"
        return 1
    fi
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

    spec_filename=$(find . -name *.spec)
    if [ ! -n "$spec_filename" ]; then
        print_out 0 "There is no SPEC file."
        return 2
    fi
    is_diff=$(git diff)
    if [ -n "$is_diff" ]; then
        print_out 0 "${is_diff}"
        print_out 0 "There is changes not committed."
        print_out 0 "Use: git commit -am 'cs10 bootstrap'"
        return 2
    fi
    prepare_rpm_topdir $pkg_dir $dist
    # Download remote sources (only) with debug enabled
    download_sources=$(spectool -g -S -D -C $source_dir $spec_dir/*.spec 2>/dev/null)
    print_out 1 $download_sources
    
    rm -f $srpm_dir/*.src.rpm
    result=$(rpmbuild -bs --define="_rpmdir ${rpm_dir}" --define="_srcrpmdir ${srpm_dir}" --define="_sourcedir ${source_dir}" --define="_specdir ${spec_dir}" --define="_builddir ${build_dir}" --define="dist ${dist}" --define="autorelease 1$dist" --define="changelog changelog" --buildroot='${buildroot_dir}' ${spec_dir}/*.spec)
    srpm_filename=$(find $srpm_dir -name *.src.rpm -printf "%f")
    if [ -n "$srpm_filename" ]; then
        print_out 0 "Build SRPM \t\tOK => $srpm_filename"
	return 0
    else
        print_out 0 "Error while building SRPM"
        print_out 0 "$result"
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
    build_dir=$(find $PWD -maxdepth 2 -name BUILD -type d)
    mkdir $build_dir/$ts
    rm $build_dir/current >/dev/null 2>&1
    ln -s $build_dir/$ts $build_dir/current
    mock -r $mock_config_path $srpm_file --resultdir $build_dir/current
    if [ $? -eq 0 ]; then
        print_out 0 "Local build \t\t[SUCCESS]"
    elif [ $? -eq 1 ]; then
        print_out 0 "Local build \t\t[ERROR] \nSee details in $build_dir/current"
        return 1
    else
        print_out 0 "Local build \t\t[ERROR] \nSee details in $build_dir/current"
        return 4
    fi
}

function build {
    target="$1"
    is_cbs_el10_builds && return 2
    prepare_mock_build $target
    create_mock_config $target
    build_srpm
    rc=$?
    if [[ $rc -ne 0 ]]; then
        return $rc
    fi
    rm -f 1000-*.patch
    git log --oneline -1 | grep -q -i -e "cs10 bootstrap" && git format-patch --start-number 1000 -N HEAD~ -o .
    mock_build $mock_config_file
    if [[ $? -eq 0 ]]; then
        cp $build_dir/current/*.rpm $repo_path
	create_repo $repo_path
        srpm_filename=$(find $build_dir/current/ -name "*.src.rpm" -printf "%f")
	log_build_order $repo_path $srpm_filename
	log_build_info $repo_path $srpm_filename
    fi
}

function log_build_info {
    repo_path="$1"
    srpm_filename="$2"
    find . -name 1000-*.patch -exec cp {} $repo_path/$srpm_filename.patch \;
    > $repo_path/$srpm_filename.buildinfo
    echo -e "$(git branch -vv)" >> $repo_path/$srpm_filename.buildinfo
    echo -e "$(git remote -v)" >> $repo_path/$srpm_filename.buildinfo
}

function log_build_order {
    repo_path="$1"
    srpm_filename="$2"
    echo -e "$srpm_filename" >> $repo_path/build_order.log
}

function print_out {
    local THIS_LEVEL=$1
    shift
    local MESSAGE="${@}"
    if [[ "${THIS_LEVEL}" -le "${VERBOSE_LEVEL}" ]]; then
       printf "${MESSAGE}\n"
    fi
}

function list_cbs_builds(){
    spec_filename=$(find . -name *.spec)
    pkg_name=$(rpmspec -P $spec_filename 2>&1 | grep -e "^Name:" | awk '{print $2}')
    cbs list-builds --package $pkg_name 2>&1
}

function is_cbs_el10_builds(){
    result=$(list_cbs_builds)
    if [[ $? -eq 0 ]]; then
       echo -e "$result" | grep -e ".el10" && return 0 || return 1
    fi
    return 1
}

