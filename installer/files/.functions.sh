#/bin/bash

function prepare_mock_build(){
    local target="${1:-messaging-rabbitmq}"
    repo_path="${HOME}/data/repos/$target"
    mock_config_file="${HOME}/workspace/$target/$target-x86_64.cfg"
}

function add_repo_readme(){
    local repo_path=${1:-$repo_path}
    cat <<EOF > $repo_path/_README.txt
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
    [ "$(ls -A $repo_path/repodata)" ] || generate_repo $repo_path
    print_out 0 "Mock conf file \t\tOK => $mock_config_file"
}

function generate_repo(){
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
    pushd $pkg_dir >/dev/null 2>&1
    is_spec_dir=$(find . -maxdepth 1 -name SPECS -type d)
    popd >/dev/null 2>&1
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
    local release=""

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
    rm -f $srpm_dir/*.src.rpm
    pushd $spec_dir >/dev/null 2>&1
    release=$(rpmautospec calculate-release | awk '{print $4}')
    if grep -q -e "autorelease" ${spec_dir}/*.spec; then
        sed -i "s/%autorelease/${release}%{?dist}/" ${spec_dir}/*.spec
        sed -i "s/%{autorelease}/${release}%{?dist}/" ${spec_dir}/*.spec
    fi
    if grep -q -e "autochangelog" ${spec_dir}/*.spec; then
        sed -i "/^%autochangelog/d" ${spec_dir}/*.spec
        sed -i "/^%{autochangelog}/d" ${spec_dir}/*.spec
        rpmautospec generate-changelog >> ${spec_dir}/*.spec
        sed -i -e '/%changelog/{n;N;N;d;}' ${spec_dir}/*.spec
    fi
    popd >/dev/null 2>&1

    # Download remote sources (only) with debug enabled
    download_sources=$(spectool -g -d "rhel ${centos_vers}" -S -D -C $source_dir $spec_dir/*.spec 2>/dev/null)
    print_out 1 $download_sources

    result=$(rpmbuild -bs --define="_rpmdir ${rpm_dir}" --define="_srcrpmdir ${srpm_dir}" --define="_sourcedir ${source_dir}" --define="_specdir ${spec_dir}" --define="_builddir ${build_dir}" --define="dist ${dist}" --buildroot='${buildroot_dir}' ${spec_dir}/*.spec)
    srpm_filename=$(find $srpm_dir -name *.src.rpm -printf "%f")
    git stash >/dev/null
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

function build {
    target="$1"
    #is_cbs_el10_builds && return 2
    prepare_mock_build $target
    create_mock_config $target
    build_srpm
    rc=$?
    if [[ $rc -ne 0 ]]; then
        return $rc
    fi
    rm -f 1000-*.patch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git diff --exit-code $current_branch origin/$current_branch >/dev/null 2>&1 || git format-patch --start-number 1000 -N HEAD~ -o .
    mock_build $mock_config_file
    if [[ $? -eq 0 ]]; then
        cp $build_dir/current/*.rpm $repo_path
	generate_repo $repo_path
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
       echo -e "$result" | grep -e ".el10" | grep -e "COMPLETE" && return 0 || return 1
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

function is_cbs_tags(){
    local tags=$1
    cbs list-tags --name=$tags >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
       echo -e "The CBS tag $target does not exist"
       return 1
    fi
    return 0
}

function upload_tarballs_to_look_aside_cache(){
    local project=$1
    local branch=$2
    shift 2
    local extra_tarballs_urls=$@
    local tarballs=""
    local tarball_urls=""
    local spec_filename=""
    local sources_dir=""
    local centos_tool_path="/tmp/centos-git-common"
    local centos_vers=10
    spec_filename=$(find . -name *.spec)
    sources_dir="SOURCES"
    if [ ! -n "$spec_filename" ]; then
        print_out 0 "There is no SPEC file."
        return 2
    fi
    [ "$(ls -A $centos_tool_path)" ] || git clone https://git.centos.org/centos-git-common $centos_tool_path
    > .${project}.metadata
    tarball_urls="$(spectool -d "rhel ${centos_vers}" -a -l $spec_filename|awk '{print $2}'|grep ^http) $extra_tarballs_urls"
    for tarball_url in $tarball_urls; do
        local _tarball=""
        _tarball=$(basename ${tarball_url})
        if ! grep -q -I . $sources_dir/$_tarball; then
            tarballs="$tarballs $_tarball"
        fi
    done
    # remove duplicates
    uniq_tarballs=$(echo -e "$tarballs" | xargs -n1 | sort -u | xargs)
    for tarball in $uniq_tarballs; do
        $centos_tool_path/lookaside_upload -f $sources_dir/$tarball -n $project -b $branch
        checksum=$(sha1sum $sources_dir/$tarball)
        echo "${checksum}" >> .${project}.metadata
        rm -f $sources_dir/$tarball
    done
    sed -i '/^$/d' .${project}.metadata
}

function update_centos_distgit(){
    local project=$1
    local branch=$2
    local spec_filename=""
    local sources_dir=""
    local sources_list=""
    local centos_vers=10
    srpm_filename=$(find . -maxdepth 1 -name "*.src.rpm" -printf "%f")
    if [ ! -n "$srpm_filename" ]; then
        print_out 0 "There is no SRPM file."
        return 2
    fi

    tmp_dir=$(mktemp -d --tmpdir=.)
    pushd $tmp_dir >/dev/null
        mkdir {SOURCES,SPECS}
        rpm2cpio ../$srpm_filename  | cpio -idm >/dev/null
        mv *.spec SPECS
        find . -maxdepth 1 -mindepth 1 -not -name SPECS -not -name SOURCES -exec mv {} SOURCES \;
        # some times tarball are downloaded by the packager so we need to include them as extra in upload_tarballs_to_look_aside_cache script
        local_tarballs=$(find SOURCES/ -type f ! -size 0 -exec grep -IL . "{}" \;)
        upload_tarballs_to_look_aside_cache $project $branch $local_tarballs
        find SOURCES -empty -type d -exec touch SOURCES/.gitkeep \;
        # Double check just in case
        is_binary_files=$(find SOURCES/ -type f ! -size 0 -exec grep -IL . "{}" \;)
        if [ -n "$is_binary_files" ]; then
            echo -e "Error: there is still a binary file in SOURCES"
            echo -e "$is_binary_files"
            popd >/dev/null
            return 4
        fi
    popd >/dev/null
    rm -rf centos_distgit >/dev/null 2>&1
    git clone -q ssh://git@git.centos.org/rpms/${project} centos_distgit
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
        git push origin ${branch}:${branch}
        if [[ $? -eq 0 ]]; then
            popd >/dev/null
            return 0
        else
            popd >/dev/null
            return 1
        fi
    else
        popd >/dev/null
        return 2
    fi
}

function build_on_cbs() {
    local target="$1"
    local project="$2"
    local mode="$3"
    if [ -d centos_distgit ]; then
        pushd centos_distgit >/dev/null
        if ! git log --pretty=oneline | grep -q -e "Import .* in CloudSIG Epoxy"; then
            echo -e "There is not import commit to build"
            popd >/dev/null
            return 1
        fi
        local commit_id=$(git log --pretty=oneline -n 1|awk '{print $1}')
        local nvr=$(git log --pretty=oneline -n1 | sed "s/.*Import \(.*\) in CloudSIG Epoxy/\1/")
        popd >/dev/null
        local srpm="git+https://git.centos.org/rpms/${project}.git#${commit_id}"
    else
        local srpm=$(find $srpm_dir -name *.src.rpm -printf "%f")
        local nvr=${srpm/.el10.src.rpm} 
    fi
    local workdir=$(mktemp -d --tmpdir=.)
    local tid=$(check_existing_build_on_cbs $workdir $nvr)
    rm -rf $workdir
    if [[ ! $mode =~ .*--scratch.* ]]; then
        local pkg_name=$(echo $nvr|rev|cut -d- -f3-|rev)
        local tag_candidate=$(echo $target|cut -d- -f -3)-candidate
        # When not building in scratch mode, if package is not in the tag, let's add.
        cbs list-pkgs --quiet --package=${pkg_name} --tag=${tag_candidate}
        if [ $? -ne 0 ]; then
            echo "Adding package ${pkg_name} to ${tag_candidate} tag"
            cbs add-pkg ${tag_candidate} ${pkg_name} --owner=jcapitao
        fi
        if [[ $tid != "KO" ]]; then
          echo "Package $nvr already built by task $tid"
          # When not building in scratch mode, if build is not already tagged, tag it.
          if ! cbs list-tagged ${tag_candidate} $pkg_name | grep -q -e $nvr; then
              echo "Build $nvr not already tagged to ${tag_candidate}, tag it"
              cbs tag-build ${tag_candidate} $nvr
          fi
          return 0
        fi
    fi
    echo "Start build of: $nvr"
    cbs build --wait $mode $target $srpm
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

function cbs_build {
    local target="cloud10s-openstack-epoxy-el10s"
    local project=$(basename $PWD)
    local branch="c10s-sig-cloud-openstack-epoxy"
    #is_cbs_el10_builds && return 2
    if [ ! -n "$target" ]; then
        echo -e "Error: needs target as argument"
        return 1
    fi
    is_cbs_target $target || return 3
    rc=$(curl -sL --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -o /dev/null -w "%{http_code}" "https://git.centos.org/rpms/$project")
    if [ $rc == "200" ]; then
        update_centos_distgit $project $branch || return 4
    fi
    sleep 5
    build_on_cbs $target $project --scratch && build_on_cbs $target $project
}

function sync_centos_to_rdo_distgit() {
    local project=$(basename $PWD)
    local pkg_info=$(rdopkg findpkg $project)
    local rdo_distgit_url=$(echo -e "$pkg_info" | grep -e "^distgit:" | awk '{print $2}')
    git clone -q $rdo_distgit_url rdo_distgit
    pushd rdo_distgit >/dev/null
    git checkout c10s-epoxy-rdo
    rsync -avz --exclude=.git ../centos_distgit/* .
    version=$(rpmspec -q SPECS/*spec --queryformat="%{VERSION}\n" 2>/dev/null|head -1)
    git add SOURCES/* SPECS/* *
    git commit -m "Update to $version"
    popd
}

function display_missing_pkgs() {
    find -name root.log -exec grep -e "No matching package to install" {} \; |  sed "s/.*'\([[:alnum:]-]*\)'/\1/"
}

function tag_build() {
    local tag=$1
    if [[ $tag == "runtime" ]]; then
        tag="cloud10s-openstack-epoxy-testing"
    elif [[ $tag == "buildtime" ]]; then
        tag="cloud10s-openstack-epoxy-el10s-build"
    else
        echo -e "Error: needs tag as argument: runtime or buildtime"
        return 1
    fi

    srpm_filename=$(find . -maxdepth 1 -name *.src.rpm -printf "%f")
    pkg=$(echo $srpm_filename | sed 's/.src.rpm/s/;s/el10ss/el10s/')
    if [ ! -n "$pkg" ]; then
        echo -e "Error: no pkg found"
        return 2
    fi

    if cbs list-tagged $tag | grep -q -e "$pkg" ; then
        echo "$pkg is already tagged"
    else
        pkg_name=$(echo -e "$srpm_filename" | rev | cut -d- -f3- | rev)
        cbs add-pkg $tag --owner jcapitao $pkg_name
        cbs tag-build --nowait $tag $pkg && cbs untag-build cloud10s-openstack-epoxy-candidate $pkg
    fi
}

function build_from_cs9() {
    local project="$1"
    local nvr="$2"
    if [ ! -n "$project" ]; then
        echo -e "Error: needs project as argument"
        return 1
    fi
    if [ ! -n "$nvr" ]; then
        echo -e "Using last NVR promoted in cloud9s-openstack-epoxy-testing"
        nvr=$(rdopkg findpkg $project | grep -e "cloud9s-openstack-epoxy-" | awk '{print $2}')
    fi
    if [ ! -n "$nvr" ]; then
        echo -e "Error: no nvr found un c9s-epoxy"
        return 1
    else
        echo -e "$nvr"
    fi
    local pkg_name=$(echo $nvr|rev|cut -d- -f3-|rev)
    local git_url=$(cbs buildinfo $nvr | grep Source | awk '{print $2}')
    if [ ! -n "$git_url" ]; then
        echo -e "Error: no git url found for nvr $nvr"
        return 1
    fi
    cbs build --scratch cloud10s-openstack-epoxy-el10s $git_url && cbs add-pkg cloud10s-openstack-epoxy-candidate --owner jcapitao $pkg_name && cbs build cloud10s-openstack-epoxy-el10s $git_url && download_cs10_rpms cloud $pkg_name
}

function download_cs10_rpms() {
    local target="$1"
    local project="$2"
    if [ ! -n "$target" ]; then
        echo -e "Error: needs target as argument"
        return 1
    fi
    if [ ! -n "$project" ]; then
        echo -e "Error: needs project as argument"
        return 1
    fi
    local nvr=$(cbs list-tagged cloud10s-openstack-epoxy-candidate | grep -e "$project" | awk '{print $1}')
    if [ ! -n "$nvr" ]; then
        echo -e "Error: no nvr found in cloud10s-openstack-epoxy-candidate for $project"
        return 1
    fi
    local cnt=$(echo -e "$nvr" | grep -c -e "$project")
    if [[ "$cnt" != "1" ]]; then
        echo -e "Error: there is more than on NVR for $project"
        echo -e "$nvr"
        return 1
    fi
    prepare_mock_build $target
    pushd $repo_path >/dev/null
    cbs download-build $nvr
    popd >/dev/null
	generate_repo $repo_path
}
