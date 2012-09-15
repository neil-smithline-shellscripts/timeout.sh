#!/bin/sh

### ################################################################
### This shell script implements a process timeout. It has been
### designed to ensure that a process terminates in a timely manner
### while using minimal computer resources.
###
### This functionality is particularly helpful when running commands
### via cron(8). The script's debugging functionality can be specially
### configured for cron-based execution.
###
### The script takes four arguments. Only the first is required. Each
### of the remaining arguments has a default value. If you wish, you
### can alter the default values in the USER CONFIGURATION section
### below.
###
### ARGUMENTS:
###
###     $1: PID of the process we are monitoring. (required)
###
###     $2: total seconds process is allowed to run before killing it.
###     (default 300: $MAXTIME_DEFAULT)
###
###     $3: seconds between checking to see if the process is still
###     alive. Lower values make timeout() more responsive but put
###     more load on your computer in general. (default 60:
###     $INTERVAL_DEFAULT)
###
###     $4: seconds to wait before escalating to the next signal in
###     $KILLSIGNALS. This is the number of seconds the monitored
###     process will have to cleanup and exit before getting hit with
###     the next signal. (default 5: $PAUSE_DEFAULT)
###
### EXIT VALUE:
###
###     0 when the monitored process exited normally
###     1 when the monitored process was terminated because it timed out
###    -1 if the monitored process couldn't be killed and is now a zombie
###
### TYPICAL USE CASES:
###
###     Interactive:
###         $ my-time-consuming-and-frequently-hanging-command &
###         $ timeout $!
###
###     Via cron:
###         sh -c 'my-time-consuming-and-frequently-hanging-command & timeout $!'
###
###     Within an existing shell script:
###         . timeout.sh
###         my-time-consuming-and-frequently-hanging-command &
###         timeout $!
###
###     When there is no need to wait for the monitored process to complete:
###         my-time-consuming-and-frequently-hanging-command & timeout $! &
###
### As a general rule, you should not need to edit this script unless
### you are following the instructions in the USER CONFIGURATION
### section. That said, should you make an improvement to the script,
### please fork the repository and submit a pull request.
### ################################################################

### ################################################################
###                 BEGIN USER CONFIGURATION
### ################################################################

# Defaults for arguments if they are not supplied on the command line.
MAXTIME_DEFAULT=300             # Default for $2
INTERVAL_DEFAULT=60             # Default for $3
PAUSE_DEFAULT=5                 # Default for $4

# Make sure that _exactly one_ of the following DEBUG functions are
# uncommented.
# DEBUG () { echo 1>&2 "DEBUG: $@"; }       # General purpose debugging.
# DEBUG () { echo 2>&1 "DEBUG: $@"; }       # Best for cron jobs.
DEBUG () { local a; }                       # Debugging disabled.

# A signal that will be ignored by the monitored process
SAFESIGNAL=INFO

# An array of increasingly more brutal signals to kill a process
KILLSIGNALS=(INT HUP KILL)

### ################################################################
###                 END USER CONFIGURATION
### ################################################################

timeout () {
    local procid=${1}; shift
    local maxtime=${1:-$MAXTIME_DEFAULT}; shift
    local interval=${1:-$INTERVAL_DEFAULT}; shift
    local pause=${1:-$PAUSE_DEFAULT}; shift

    local cause='Died a natural death.'
    local return_val=0
    local iterations
    let iterations=$maxtime/$interval

    # Loop while the process is still alive
    DEBUG "$procid: Running for $maxtime seconds ($interval seconds X $iterations iterations)."
    while still_alive ${procid}; do
        # See if it is time to kill it
        if [ $iterations -eq 0 ]; then
            # Let's kill it by looping through the signals in $KILLSIGNALS
            cause='KILLED!'
            return_val=1
            timeout_kill $procid $pause $KILLSIGNALS
            break
        else
            # Let's wait a bit and loop again
            DEBUG "$procid: Still has $iterations iterations of $interval seconds left to live."
            let iterations=iterations-1
            sleep $interval
        fi
    done

    # We are here either because the loop ended naturally when the
    # process finished or we tried to kill it. We'll set our return
    # status to indicate if the process is dead or not and print some
    # debugging output.
    if still_alive ${procid}; then
        DEBUG "$procid: ZOMBIED!"
        return -1
    else
        DEBUG "$procid: $cause"
        return $return_val
    fi
}

# Return success if process $1 is alive, failure otherwise.
# Process $1 must ignore $SAFESIGNAL.
still_alive () {
    send_signal $SAFESIGNAL $1
}

# Send signal $1 to process $2 without any output.
# Returns the return value of the kill command.
send_signal () {
    kill -${1} ${2} >/dev/null 2>&1
}

# Kill a process until it's dead or a zombie.
# $1: process id
# $2: time to wait between signals
# $3-*: list of signals to to send
timeout_kill () {
    local procid=$1; shift
    local pause=$1; shift
    local i

    for i; do
        DEBUG "$procid: kill -$i"
        send_signal $i ${procid}
        sleep ${pause}
        if ! still_alive ${procid}; then
            break
        fi
    done
}
