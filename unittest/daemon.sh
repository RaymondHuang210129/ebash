#!/usr/bin/env bash

source ${ETEST_TOPDIR}/unittest/daemon_expect.sh

ETEST_daemon_init()
{
    local pidfile_real="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon     \
        "${DAEMON_EXPECT[@]}"    \
        name="Init Test Daemon"  \
        cmdline="sleep infinity" \
        pidfile="${pidfile_real}"

    $(pack_import sleep_daemon)

    assert_eq "Init Test Daemon" "${name}"
    assert_eq "sleep infinity"   "${cmdline}"
    assert_eq "${pidfile_real}"  "$(pack_get sleep_daemon pidfile)"
}

ETEST_daemon_start_stop()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    etestmsg "Starting infinity daemon"
    daemon_init sleep_daemon            \
        "${DAEMON_EXPECT[@]}"           \
        name="Test Daemon"              \
        cmdline="sleep infinity"        \
        cgroup="${ETEST_CGROUP}/daemon" \
        pidfile="${pidfile}"

    daemon_start sleep_daemon

    # Wait for process to be running
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon

    # Now stop it and verify proper shutdown
    local pid=$(cat "${pidfile}")
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}

ETEST_daemon_netns()
{
# This test is different.  12.04 doesn't have a way to ask the system what netns
# a program is running in, and it's difficult to tell when you are in a namespace
# that you are there, and if you are there, which one you are in.
#
# So, I'm naming the internal nic something unique that I can look for.  Then I
# I run a script in the namespace that will return 1 if the nic doesn't exist and
# sleep forever (like a daemon) if it does find it.

    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    local testns_args

    netns_init testns_args       \
        ns_name=testns           \
        devname=testns_eth0      \
        peer_devname=eth0_testns \
        connected_nic=eth0       \
        bridge_cidr=127.0.0.2/24 \
        nic_cidr=127.0.0.3/24

    $(pack_import testns_args)

    assert_false netns_exists ${ns_name}

    etestmsg "Creating namespace"
    netns_create ${ns_name}

    assert netns_exists ${ns_name}

    etestmsg "Creating network in namespace"
    netns_setup_connected_network testns_args

    # This script is run from the directory output/daemon.sh/ETEST_daemon.sh/, 
    # which is a transient directory that only exists during the test run and
    # is cleaned up immediately after.  Regardless, that is why the cmdline
    # specifies the script to run the way it does.
    etestmsg "Starting infinity daemon"
    daemon_init sleep_daemon                        \
        "${DAEMON_EXPECT[@]}"                       \
        name="Netns test daemon"                    \
        cmdline="../../../unittest/netns_runner.sh" \
        netns_name=testns                           \
        cgroup="${ETEST_CGROUP}/daemon"             \
        pidfile="${pidfile}"

    echo $(lval +sleep_daemon)

    $(pack_import sleep_daemon)

    daemon_start sleep_daemon

    etestmsg "Waiting for infinity daemon"
    # Wait for process to be running
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon

    # Now stop it and verify proper shutdown
    local pid=$(cat "${pidfile}")
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile

    netns_remove_network testns_args
    netns_delete ${ns_name}

    assert_false netns_exists ${ns_name}
}

ETEST_daemon_cgroup()
{
    CGROUP=${ETEST_CGROUP}/daemon
    cgroup_create ${CGROUP}

    local pidfile="${FUNCNAME}.pid"

    etestmsg "Initializing daemon"
    daemon_init sleep_daemon      \
        "${DAEMON_EXPECT[@]}"     \
        name="cgroup test daemon" \
        cmdline="sleep infinity"  \
        cgroup=${CGROUP}          \
        pidfile="${pidfile}"

    etestmsg "Running daemon"
    daemon_start sleep_daemon
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]

    local running_pids=$(cgroup_pids ${CGROUP})
    etestmsg "Daemon running $(lval CGROUP running_pids)"
    cgroup_pstree ${CGROUP}

    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    local stopped_pids=$(cgroup_pids ${CGROUP})
    assert_empty "${stopped_pids}"
}

ETEST_daemon_hooks()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon     \
        "${DAEMON_EXPECT[@]}"    \
        name="hooks daemon"      \
        cmdline="sleep infinity" \
        pidfile="${pidfile}"     \
        respawns="3"             \
        respawn_interval="1"

    # START
    daemon_start sleep_daemon
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon

    # STOP
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    assert_false daemon_running sleep_daemon
}

# Ensure if pre_start hook fails we won't call start
ETEST_daemon_pre_start_fail()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon                      \
        name="pre_start_fail daemon"              \
        cmdline="sleep infinity"                  \
        pidfile="${pidfile}"                      \
        pre_start="false"                         \
        pre_stop="touch ${FUNCNAME}.pre_stop"     \
        post_start="touch ${FUNCNAME}.post_start" \
        post_stop="touch ${FUNCNAME}.post_stop"   \
        respawns="3"                              \
        respawn_interval="1"                      \

    # START
    daemon_start sleep_daemon
    eretry -T=30s daemon_not_running sleep_daemon
    assert_not_exists ${FUNCNAME}.post_start
}

# Ensure logfile works inside daemon
ETEST_daemon_logfile()
{
    eend()
    {
        true
    }

    launch()
    {
        echo "stdout" >&1
        echo "stderr" >&2
        sleep infinity
    }

    local mdaemon
    daemon_init mdaemon      \
        "${DAEMON_EXPECT[@]}"\
        name="My Daemon"     \
        cmdline="launch"

    $(pack_import mdaemon logfile)

    (
        die_on_abort

        etestmsg "Starting daemon"
        daemon_start mdaemon
        daemon_expect pre_start
        daemon_expect post_start
        assert_true daemon_running mdaemon

        etestmsg "Stopping daemon"
        daemon_stop mdaemon &
        daemon_expect pre_stop
        daemon_expect post_stop
        wait
        assert_true daemon_not_running mdaemon
    )

    # Show logfile and verify state
    etestmsg "Daemon logfile:"
    cat "${logfile}"

    grep --silent "Starting My Daemon" "${logfile}"
    grep --silent "stdout"             "${logfile}"
    grep --silent "stderr"             "${logfile}"
    grep --silent "Stopping My Daemon" "${logfile}"
}

ETEST_daemon_respawn()
{
    touch ${DAEMON_LOCK}
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon     \
        "${DAEMON_EXPECT[@]}"    \
        name="respawning daemon" \
        cmdline="sleep infinity" \
        pidfile="${pidfile}"     \
        respawns="3"             \
        respawn_interval="300"

    $(pack_import sleep_daemon)
    etestmsg "Starting daemon $(lval +sleep_daemon)"
    daemon_start sleep_daemon

    # Wait for pre_start and "start" states then daemon must be running
    daemon_expect pre_start
    daemon_expect post_start
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon
    assert process_running $(cat ${pidfile})

    # Now kill it the specified number of respawns
    # and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        pid=$(cat "${pidfile}")
        etestmsg "Killing daemon $(lval pid iter respawns)"
        ekilltree -s=KILL ${pid}

        # Wait for "crash" state. Daemon must be NOT running now.
        daemon_expect post_crash
        assert daemon_not_running sleep_daemon
        assert process_not_running ${pid}

        # If iter == respawns break out
        [[ ${iter} -lt ${respawns} ]] || break

        # Now wait for process to respawn
        etestmsg "Waiting for daemon to respawn"
        daemon_expect pre_start
        daemon_expect post_start
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon
        assert process_running $(cat ${pidfile})
    done

    # Process should NOT be running and should NOT respawn b/c we killed it too many times
    etestmsg "Waiting for daemon to abort"
    daemon_expect post_abort
    assert_false process_running $(cat ${pidfile})
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    daemon_stop sleep_daemon
}

# Modified version of above test which gives a large enough window between kills
# such that it should keep respawning (b/c/ failed count resets)
ETEST_daemon_respawn_reset()
{
    touch ${DAEMON_LOCK}
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon        \
        "${DAEMON_EXPECT[@]}"       \
        name="respawn_reset daemon" \
        cmdline="sleep infinity"    \
        pidfile="${pidfile}"        \
        respawns="3"                \
        respawn_interval="0"

    $(pack_import sleep_daemon)
    etestmsg "Starting daemon $(lval +sleep_daemon)"
    daemon_start sleep_daemon

    # Wait for pre_start and "start" states then daemon must be running
    daemon_expect pre_start
    daemon_expect post_start
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon
    assert process_running $(cat ${pidfile})

    # Now kill it the specified number of respawns and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        local pid=$(cat "${pidfile}")
        etestmsg "Killing daemon $(lval pid iter respawns)"
        ekilltree -s=KILL ${pid}

        # Wait for "crash" state. Daemon must be NOT running now.
        daemon_expect post_crash
        assert daemon_not_running sleep_daemon
        assert process_not_running ${pid}

        # Now wait for process to respawn
        etestmsg "Waiting for daemon to respawn"
        daemon_expect pre_start
        daemon_expect post_start
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon
        assert process_running $(cat ${pidfile})
    done

    # Now stop it and verify proper shutdown
    etestmsg "Stopping daemon and waiting for shutdown"
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait

    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}
