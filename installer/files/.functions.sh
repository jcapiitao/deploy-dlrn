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
    local centos_vers=10
    local dist=.el${centos_vers}s

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
    download_sources=$(spectool -g -d "rhel ${centos_vers}" -S -D -C $source_dir $spec_dir/*.spec 2>/dev/null)
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
    if [ ! -n "$srpm_file" ]; then
        srpm_file=$(find $PWD -maxdepth 1 -name *.src.rpm -type f)
    fi
    if [ ! -n "$mock_config_path" ]; then
        echo -e "Error: needs mock_config_path as argument"
        return 1
    fi
    build_dir=$(find $PWD -maxdepth 2 -name BUILD -type d)
    ts=$(date +"%Y-%m-%d-%H-%M-%S")
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

function cbs_build {
    target="$1"
    srpm_file="$2"
    is_cbs_el10_builds && return 2
    if [ ! -n "$srpm_file" ]; then
        srpm_file=$(find $PWD -maxdepth 1 -name *.src.rpm -type f)
    fi
    if [ ! -n "$target" ]; then
        echo -e "Error: needs target as argument"
        return 1
    fi
    is_cbs_target $target && return 2
    build_dir=$(find $PWD -maxdepth 2 -name BUILD -type d)
    ts=$(date +"%Y-%m-%d-%H-%M-%S")
    mkdir $build_dir/$ts
    rm $build_dir/current >/dev/null 2>&1
    ln -s $build_dir/$ts $build_dir/current
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

function is_cbs_target(){
    local target=$1
    cbs list-targets --name=$target >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
       echo -e "The CBS target $target does not exist"
       return 1
    fi
    return 0
}

function upload_tarballs_to_look_aside_cache(){
    local project=$1
    local branch=$2
    local tarball=""
    local tarball_url=""
    local spec_filename=""
    local sources_dir=""
    local centos_tool_path="/tmp/centos-git-common"
    local centos_vers=10
    spec_filename=$(find . -name *.spec)
    sources_dir=$(find . -maxdepth 1 -name SOURCES -type d)
    if [ ! -n "$spec_filename" ]; then
        print_out 0 "There is no SPEC file."
        return 2
    fi
    [ "$(ls -A $centos_tool_path)" ] || git clone https://git.centos.org/centos-git-common $centos_tool_path
    > .${project}.metadata
    spectool -d "rhel ${centos_vers}" -a -l $spec_filename|awk '{print $2}'|grep ^http|while read tarball_url
    do
        tarball="$(basename ${tarball_url})"
        #$centos_tool_path/lookaside_upload -f $tarball -n $project -b $branch
        echo -e "Uploading $tarball -n $project -b $branch"
        checksum=$(sha1sum $tarball)
        echo "${checksum}" >> .${project}.metadata
        rm -f ${tarball}
    done
}

function update_centos_distgit(){
    local project=$1
    local branch=$2
    local spec_filename=""
    local sources_dir=""
    local sources_list=""
    local centos_vers=10
    srpm_filename=$(find . -maxdepth 1 -name "*.src.rpm" -printf "%f")
    tmp_dir=$(mktemp -d --tmpdir=.)
    pushd $tmp_dir >/dev/null
        mkdir {SOURCES,SPECS}
        rpm2cpio ../*.src.rpm  | cpio -idm >/dev/null
        sources_list=$(spectool -d "rhel $centos_vers" -a -l *.spec 2>/dev/null | awk '{print $2}' | grep -v -e "^http")
        mv $sources_list SOURCES
        mv *.spec SPECS
        upload_tarballs_to_look_aside_cache $project $branch
    popd >/dev/null
    [ "$(ls -A centos_distgit >/dev/null 2>&1)" ] || git clone -q ssh://git@git.centos.org/rpms/${project} centos_distgit
    pushd centos_distgit >/dev/null
    if git branch -a | grep -q $branch; then
        git checkout $branch
    else
        git checkout -b $branch
    fi
    rsync -a ../${tmp_dir}/SPECS ../${tmp_dir}/SOURCES ../${tmp_dir}/.${project}.metadata .
    rm -rf ../$tmp_dir >/dev/null
    git add .

    # If there are changes commit and push
    if [ $(git status|grep -c "^nothing to commit") -eq 0 ]; then
        git config --add user.name "Joel Capitao"
        git config --add user.email "jcapitao@redhat.com"
        nvr=$(basename $srpm_filename .src.rpm)
        git commit -m "Import $nvr in CloudSIG Epoxy"
        #git push origin ${branch}:${branch}
    fi
    popd >/dev/null
}

function build_on_cbs() {
    local target="$1"
    local project="$2"
    local mode="$3"
    pushd centos_distgit >/dev/null
    if ! git log --pretty=oneline | grep -q -e "Import .* in CloudSIG Epoxy"; then
        echo -e "There is not import commit to build"
        popd >/dev/null
        return 1
    fi
    local commit_id=$(git log --pretty=oneline -n 1|awk '{print $1}')
    popd >/dev/null
    local distgit_url="git+https://git.centos.org/rpms/${project}.git#${commit_id}"
    local srpm_filename=$(find . -maxdepth 1 -name "*.src.rpm" -printf "%f")
    local nvr=$(basename $srpm_filename .src.rpm)
    local workdir=$(mktemp -d --tmpdir=.)
    local tid=$(check_existing_build_on_cbs $workdir $nvr)
    rm -rf $workdir
    if [[ ! $mode =~ .*--scratch.* ]]; then
        local pkg_name=$(echo $nvr|rev|cut -d- -f3-|rev)
        # When not building in scratch mode, if package is not in the tag, let's add.
        cbs list-pkgs --quiet --package=${pkg_name} --tag=${target}
        if [ $? -ne 0 ]; then
            echo "Adding package ${pkg_name} to ${target} tag"
            cbs add-pkg ${target} ${pkg_name} --owner=jcapitao
        fi
        if [[ $tid != "KO" ]]; then
          echo "Package $nvr already built by task $tid"
          # When not building in scratch mode, if build is not already tagged, tag it.
          if ! cbs list-tagged ${target} $pkg_name | grep -q -e $nvr; then
              echo "Build $nvr not already tagged to ${target}, tag it"
              cbs tag-build ${target} $nvr
          fi
          return 0
        fi
    fi
    echo "Start build of: $nvr"
    #cbs build --wait $mode $target $distgit_url
}

function check_existing_build_on_cbs() {
    local workdir=$1
    local nvr=$2
    cbs buildinfo $nvr &> $workdir/check_existing_build_output
    tid=$(awk '/Task:/ { print $2 }' $workdir/check_existing_build_output)
    state=$(awk '/State:/ { print $2 }' $workdir/check_existing_build_output)
    if [ "${state,,}" = "complete" ]; then
        echo "$tid"
        return 0
    else
        echo "KO"
        return 1
    fi
}
