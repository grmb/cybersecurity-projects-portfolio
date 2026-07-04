#!/bin/bash

# ==============================================================================
# LOCAL SYSTEM AUDIT DISCLAIMER & RESPONSIBLE USE POLICY
# ==============================================================================
# LOCAL SCANNER DISCLAIMER & RESPONSIBLE USE POLICY
# This system information utility was developed as an educational coursework 
# project. It is strictly non-destructive, read-only, and does not require 
# root/administrative (sudo) privileges.
#
# INTENDED USE & PRIVACY NOTICE:
# This tool is designed to collect and display local system metrics, including 
# network identifiers (IP/MAC addresses) and resource utilization stats. 
# Execute this tool only on devices you own or are explicitly authorized to audit. 
# Handle the output securely, as it contains sensitive network configuration details.
#
# NO-WARRANTY & LIMITATION OF LIABILITY:
# This script is provided "AS IS" without any warranties. While it does not 
# modify any system files, the author assumes no 
# liability for temporary performance spikes (e.g., high disk I/O during large 
# file searches) or any security alerts triggered by network data collection.
# ==============================================================================

# Features
# 1. Identification of public and private IP
# 2. Identification of system's MAC address (sensitive portions masked)
# 3. Displays top five processes using the most percentage of CPU processing
# 4. Total and available memory display
# 5. Display of active systems and their status
# 6. Display of top 10 largest files located in the /home directory.


# Usage: Run either ./system-scanner.sh or sudo ./system-scanner.sh
# Note: sudo permission is needed if there are multiple users.


# Identify the system's public IP. 
# Here, we can use ifconfig.me to check the system's public IP address.

get_public_IP() {
# Use curl command and stringify the output for display.
    public_IP=$(curl -s ifconfig.me)
}

# Identify the private IP address assigned to the system's network interface.
get_private_IP() {
# Retrieve the IP address of the hostname, and print the first one in case there are multiple results for hostname -I
    private_IP=$(hostname -I)
}
 
# Display the MAC address (masking sensitive portions for security).
get_mac_address() {
# Use ifconfig to retrieve the address, but this will print multiple lines.
# So, we need to search the specific data, which is ether in this case. It stands for Ethernet address and is the same as MAC address
# Once the line is found, print the second string, which is the actual MAC address, and save it in mac_addr for later processing.
    mac_addr=$(ifconfig | grep 'ether' | awk {'print $2'})
    
# Masking the sensitive portion. Cut will set delimiter to colon, then -f1-3 keeps fields 1 to 3 (i.e. xx:xx:xx).
# Then sed replaces the cut out portion with :xx:xx:xx, so first three parts of the MAC address is unmasked, while the last three are masked.
   mac_addr_masked=$(echo $mac_addr | cut -d':' -f1-3 | sed 's/$/:XX:XX:XX/')    
}

# Display the percentage of CPU usage for the top 5 processes.
get_cpu_usage_top_five() {
# Get entire table first
# sort data retrieved by ps, then display cpu%, command
 cpu_usage=$(ps -eo pcpu,comm --sort=-pcpu | head -n 6)
}

# Display memory usage statistics: total and available memory. 
get_memory_usage_stats() {
  # free -h will display memory details, but we will need to remove Swap memory as it is not needed. Only first two rows are needed.
  # Then, print columns 2 and 4 (Total and available memories), then make the output neater with column -t.	
  mem_stats=$(free -h | awk 'NR==1{print "Total","Available"} NR==2 {print  $2, $4}' | column -t)
}

# List active system services with their status. 
get_active_systems() {
  sys_list=$(systemctl list-units --type=service --state=active | head -n -6)
}

# Locate the Top 10 Largest Files in /home. 
get_home_largest_files() {
	# This will search recursively starting in the /home directory, and limited to files only.
	# Next, du will be executed without including subdirectories (-S) and make the output human readable (-h).
	# Next, output will be sorted with sort -rh, largest file first, then show only the top 10 largest files.
    largest_files=$(find /home -type f -exec du -Sh {} + | sort -rh | head -n 10)
}

# Display all the statistics needed
display_statistics() {
# -e in echo enables interpretation of backslashes for adding additional newline with \n
# This is to enhance output readability by adding spacing between each data set.
   echo -e "Public IP: $public_IP\n"	
   
   echo -e "Private IP: $private_IP\n"
   
   echo -e "MAC address (masked): $mac_addr_masked\n"
   
   echo "Top 5 processes by CPU usage"
   echo -e "$cpu_usage\n"
   
   echo "Memory usage statistics"
   echo -e "$mem_stats\n"
   
   echo "Active systems and status"
   echo -e "$sys_list\n"
   
   echo "Top 10 largest files"
   echo "$largest_files"
}

# Execute the functions in order listed below.
# Get the needed data first, store them in variables, then display them in display_statistics
get_public_IP
get_private_IP
get_mac_address
get_cpu_usage_top_five
get_memory_usage_stats
get_active_systems
get_home_largest_files
display_statistics
