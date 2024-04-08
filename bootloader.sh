#!/usr/bin/env bash
# KaguOS bootloader

# Helper function to print fatal error and terminate the program
function exit_fatal {
    echo "FATAL ERROR: $1"
    exit 1
}
export -f exit_fatal


# Parse bootloader arguments to handle debug options if needed:
# Check input arguments for debug flags
export DEBUG_JUMP="0"
export DEBUG_VJUMP="0"
export DEBUG_SLEEP="0"
for IN_ARG in "$@"; do
    case "${IN_ARG}" in
        --debug-jump|-j)
            echo "Note: Debug jump enabled"
            export DEBUG_JUMP="1"
            ;;
        --debug-vjump|-vj)
            echo "Note: Debug virtual jump enabled"
            export DEBUG_VJUMP="1"
            ;;
        --debug-sleep=|-s=*)
            export DEBUG_SLEEP="${IN_ARG#*=}"
            if [[ ! ${DEBUG_SLEEP} =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                echo "Incorrect format for debug sleep parameter. It will be reset to 0."
                export DEBUG_SLEEP="0"
            fi
            echo "Note: Debug sleep interval set to ${DEBUG_SLEEP}"
            ;;
        --help|-h)
            echo "KaguOS bootloader"
            echo "KaguOS bootloader"
            echo "Usage: bootloader.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --debug-jump, -j  Debug jump enabled"
            echo "  --debug-vjump, -vj Debug virtual jump enabled"
            echo "  --debug-sleep=, -s= Debug sleep interval in seconds(e.g. use 0.5 for 500ms), default is 0 - no sleep between command execution"
            echo "  --help, -h        Print this help message"
            exit 0
            ;;
        *)
            exit_fatal "Unknown argument: ${IN_ARG}."
            ;;
    esac
done

#################################
# BOOTLOADER:                   #
#################################


# Lets include some human readable names for addresses to simplify reading and writing the code
source include/defines.sh
source "${GLOBAL_ENV_FILE}"



###########################
#######  INIT HW  #########
# We use text files to emulate HW and simplify debug
# so lets remove files from previous boot:
rm -rf "${GLOBAL_HW_DIR}"
mkdir -p "${GLOBAL_HW_DIR}"

# Init RAM with zero:
# NOTE: Real computer has a memory with some size which is reset to some default values on power off.
for ((i=1;i<=${GLOBAL_RAM_SIZE};i++)); do
    HW_RAM_MEMORY[$i]="0"
done

# Init basic functionality of CPU, RAM, display and keyboard.
# NOTE: real computer does it with giving a power to some modules
#       therefore some initial values and state are ready for further usage.
# NOTE AI: Ask AI assistant about source command in bash.
source include/hw/cpu.sh
source include/hw/ram.sh
source include/hw/input_output.sh
####### INIT HW END #######
###########################



###########################
####### LOAD KERNEL #######
# Write debug line to mark kernel start address
write_to_address ${GLOBAL_KERNEL_START_INFO_ADDRESS} "############ KERNEL START ###########"

# Load data from disk to RAM:
# NOTE: Real computer loads kernel from disk or disk partition
#       so some basic disk driver should be present in bootloader.
# NOTE AI: Ask AI assistant about file reading in loop as below.
CUR_ADDRESS="${GLOBAL_KERNEL_START}"
while read -r LINE; do
    write_to_address ${CUR_ADDRESS} "${LINE}"
    CUR_ADDRESS=$((CUR_ADDRESS + 1))
done < "${GLOBAL_KERNEL_DISK}"

# Write debug line to mark kernel end address
write_to_address ${CUR_ADDRESS} "############ KERNEL END #############"
CUR_ADDRESS=$((CUR_ADDRESS + 1))
write_to_address ${GLOBAL_KERNEL_END_INFO_ADDRESS} "${CUR_ADDRESS}"
####### LOAD KERNEL END ###
###########################



###########################
####### JUMP TO KERNEL ####
# Jump to the address in RAM
# where the kernel was loaded:
source include/jump.sh
source include/stack.sh
source include/function.sh
source include/process.sh

# Reset scheduler variables to 0 so we will start in kernel mode
write_to_address ${GLOBAL_SCHED_COUNTER_ADDRESS} "0"
write_to_address ${GLOBAL_SCHED_PID_ADDRESS} "0"
jump_to ${GLOBAL_KERNEL_START}

# Run kernel main loop.
# NOTE: Real CPU has a control unit to handle switch between instructions
#      while our emulation uses eval function of bash to achieve similar behavior.
# NOTE AI: Ask AI assistant about eval command and potential security issues of its usage for scripts.
while [ 1 = 1 ]
do
    SCHED_COUNTER=$(read_from_address ${GLOBAL_SCHED_COUNTER_ADDRESS})
    # echo "$(read_from_address ${SCHED_COUNTER})"
    SCHED_PID=$(read_from_address ${GLOBAL_SCHED_PID_ADDRESS})
    if [ "${SCHED_PID}" = "0" ] || [ "${SCHED_COUNTER}" = "0" ]; then
        # Go to the next command:
        jump_increment_counter
        if [ "${DEBUG_JUMP}" = "1" ]; then
            jump_print_debug_info
        fi

        # Check whether next command points to termination
        NEXT_CMD=$(read_from_address ${GLOBAL_NEXT_CMD_ADDRESS})
        if [ "${NEXT_CMD}" = "${GLOBAL_TERMINATE_ADDRESS}" ]; then
            write_to_address ${GLOBAL_DISPLAY_ADDRESS} "Kernel stopped"
            display_success
            break
        fi

        eval $(read_from_address ${NEXT_CMD}) || exit_fatal "Incorrect instruction"
        dump_RAM_to_file
    else
        if [ "${GLOBAL_SCHED_COUNTER_ADDRESS}" = "100" ]; then
            write_to_address ${GLOBAL_SCHED_COUNTER_ADDRESS} ${SCHED_COUNTER}
        else
            write_to_address ${GLOBAL_SCHED_COUNTER_ADDRESS} "$(($SCHED_COUNTER - 1))"
        fi
        v_jump_increment_counter

        OFFSET=$(get_process_mem_offset $(read_from_address ${GLOBAL_CURRENT_PID_INFO_ADDRESS}))
        NEXT_CMD=$(v_read_from_address ${LOCAL_NEXT_CMD_ADDRESS} )
        NEXT_CMD_VAL=$(v_read_from_address ${NEXT_CMD})
        if [ "${DEBUG_VJUMP}" = "1" ]; then 
            print_process_id
            echo -e "\033[92m$(v_read_from_address ${NEXT_CMD})\033[0m"
        fi
        eval $(v_read_from_address ${NEXT_CMD}) || exit_fatal "Incorrect instruction"
        dump_RAM_to_file
    fi
    sleep ${DEBUG_SLEEP}
done

###### END JUMP TO KERNEL #
###########################
