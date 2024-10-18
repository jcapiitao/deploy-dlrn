#/bin/bash

function create_mock_config(){
    CHROOT="${1:-messaging10s-rabbitmq}"
    REPO_NAME="$(echo -e $CHROOT | cut -d- -f2)-deps"
    REPO_PATH="${HOME}/data/repos/${REPO_NAME}"
    MOCK_CONFIG_FILE="${HOME}/workspace/${CHROOT}-x86_64.cfg"
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

function build_srpm(){
    VERBOSE_LEVEL='0'
    PKG=$(basename $(pwd))
    RPMBUILDDIR=$PWD/rpmbuild
    dist=el10s

    rm -rf $RPMBUILDDIR >/dev/null 2>&1
    mkdir -p $RPMBUILDDIR/SPECS \
             $RPMBUILDDIR/BUILD \
             $RPMBUILDDIR/SOURCES \
             $RPMBUILDDIR/BUILDROOT \
             $RPMBUILDDIR/SRPMS \
             $RPMBUILDDIR/RPMS
    
    # Download remote sources (only) with debug enabled
    download_sources=$(spectool -g -S -D -C $RPMBUILDDIR/SOURCES *.spec 2>/dev/null)
    print_out 1 $download_sources
    local_sources=$(rpmspec -q --define "_topdir $RPMBUILDDIR" -P *.spec 2>/dev/null | grep -e "^Source" -e "^Patch" | awk '{print $2}' | grep -v -e "^http" | tr '\n' ' ')
    if [ -n "$local_sources" ]; then 
        for f in $local_sources; do
            [ -f "$f" ] && cp $f $RPMBUILDDIR/SOURCES && print_out 1 "$f was copied to $RPMBUILDDIR/SOURCES"
	done
    fi
    cp *.spec $RPMBUILDDIR/SPECS
    print_out 0 "Build SRPM init \tOK"
    
    pushd $RPMBUILDDIR >/dev/null
    srpm_build=$(rpmbuild --define "_topdir $RPMBUILDDIR" --define "dist .$dist" -bs SPECS/*.spec 2>&1)
    srpm_filename=$(find $RPMBUILDDIR/SRPMS/ -name *.src.rpm -printf "%f")
    if [ -n "$srpm_filename" ]; then
        print_out 0 "Build SRPM \t\tOK => $srpm_filename"
    else
        print_out 0 "Error while building SRPM"
        print_out 0 "$srpm_build"
        popd >/dev/null
        return 1
    fi
    popd >/dev/null
}

function print_out {
    local THIS_LEVEL=$1
    shift
    local MESSAGE="${@}"
    if [[ "${THIS_LEVEL}" -le "${VERBOSE_LEVEL}" ]]; then
       printf "${MESSAGE}\n"
    fi
}
