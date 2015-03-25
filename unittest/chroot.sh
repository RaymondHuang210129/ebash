## Check if we're root and re-execute if we're not through sudo ##
if [[ $(id -u) != "0" ]]; then
    sudo -E "$0" "$@"
    exit $?
fi

# Global settings
BASHUTILS=.
$(esource chroot.sh)
CHROOT=build
CHROOT_MOUNTS=( /dev /proc /sys )

check_mounts()
{
    $(declare_args assert_count)

    # Verify chroot paths not mounted
    for path in ${CHROOT_MOUNTS[@]}; do
        [[ ${assert_count} -eq 0 ]] && assert_false emounted ${CHROOT}${path} || assert_true emounted ${CHROOT}${path}
        assert_eq ${assert_count} $(emounted_count ${CHROOT}${path})
    done
}

ETEST_chroot_create_mount()
{
    {
        mkchroot ${CHROOT} precise oxygen bdr-jenkins amd64
        trap_add "chroot_exit &>/dev/null" HUP INT QUIT BUS PIPE TERM EXIT

        # Verify chroot paths not mounted
        check_mounts 0

        # Mount a few times and verify counts go up
        for (( i=0; i<3; ++i )); do
            chroot_mount
            check_mounts $((i+1))
        done

        # Unmount and verify counts go down
        for (( i=3; i>0; --i )); do
            chroot_unmount
            check_mounts $((i-1))
        done
    } &> $(edebug_out)
}
