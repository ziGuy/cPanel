#file=/root/cpInactiveAcct.sh; curl -s http://guyziv.ddns.net/scripts/archive%5C%5CcpInactiveAcct.txt | sed -e $'s/\r$//'>$file && chmod 700 $file && $file

#!/bin/bash

# Last update: 1-MAR-2016
# Author: guyziv84@gmail.com
#
# This script will go through all cpanel accounts and check whether
# each account is active according to dns records (a and mx), resolving from
# an external dns server.
# Please note that if an account is using an external redirection
# like Cloudflare, it will be considered as inactive.
# ns records are NOT being checked.
# In the end of the scanning you can choose to automatically suspend all,
# inactive accounts, and in the next run you can choose to terminate those.
# You can also terminate only suspended accounts that have been suspended 3 month ago.



###################### USER VARIABLES ######################
skipdomain=()
# if you want to ignoe all subdomains, put a dot in the begining e.g. ".domainname.com"
# seperate valus with spaces (e.g. (.sub.domain.co.il domain.co.il))

skipsizecheck=0 # value of '1' will significantly improve performance.
accexp=*
#possible values: *, c*, [a-fA-f]*, da[0-4]r*, [f-m]*
############################################################




#set -x


mkdir -p ~/cpinactiveacct
mkdir -p ~/cpinactiveacct/curacct

skipdomnum=${#skipdomain[@]}
skipdomfile=~/cpinactiveacct/cpinactiveacct-skipdomfile
>$skipdomfile echo

localips=~/cpinactiveacct/cpinactiveacct-localips
ifconfig | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}' | grep -v 127.0.0.1 >$localips || echo "Critical error: Can't create localips file\!"

procacctnum=0
actaccnum=0
inactaccunsuspendednum=0
inactaccspendednum=$(for var in /var/cpanel/suspended/*; do [[ $(grep "cpInactiveAcct.sh" $var) ]] && echo $var; done | wc -l)
cumsize=0

activeacct=/var/log/cpinactiveacct-activeacctlist.csv
inactiveacctunsuspended=/var/log/cpinactiveacct-inactiveacctunsuspended.csv
inactiveacctsuspended=/var/log/cpinactiveacct-inactiveacctsuspended.csv




function accinfoheaders(){
echo user,mail,size
}


function acctSize() {
        dirS=0; sqlS=0; sumS=0
        dirS=$(du -s "/home/$1" | awk '{print $(NF-(NF-1))}')
        sqlS=$(find /var/lib/mysql/ -name "$1*" -exec du -ks {} \; | cut -f1)
        sqlS=$( echo $sqlS | awk '{printf("%d\n",$(NF-(NF-1)) + 0.5)}')
        sumS=$((dirS+sqlS))
}

function accinfo(){
        echo -n "$curusr,"
        if [[ $(egrep CONTACTEMAIL2=[[:alnum:]] $curacct ) ]]; then
                echo -n "$(grep "CONTACTEMAIL" $curacct | cut -d = -f 2 | egrep ^[[:alnum:]] | tr '\n' ';' | rev | cut -c 2- | rev)"
        else
                echo -n "$(grep "CONTACTEMAIL" $curacct | cut -d = -f 2 | egrep ^[[:alnum:]])"
        fi
        if [[ $skipsizecheck = 0 ]]; then
        {
                acctSize $curusr
                echo ",account size: $(($sumS/1024)) MB"
                [[ $activeflag = 0 ]] && cumsize=$((cumsize+sumS))
        } else {
            echo;
        }
        fi
}

function suspendAcct() {
	echo
	read -n 1 -p "Do you want to suspend ALL accounts in $inactiveacctunsuspended? (y/n): " rusure;
	case $rusure in
		y|Y|yes|Yes|YES) echo -e "\n\e[1;31mLET ME ASK YOU THIS ONE MORE TIME.\nARE YOU SURE YOU WANT TO SUSPEND ALL ACCOUNTS IN $inactiveacctunsuspended? IF YOU ARE SURE, TYPE 'yes'\e[0m"
		 read rusuredc
		 case $rusuredc in
			yes) if [[ "$rusuredc" == "yes" ]]; then for user in $(awk -F, '{print $1}' $inactiveacctunsuspended | tail -n +2); do /scripts/suspendacct $user "cpInactiveAcct.sh - Contact Guy Ziv before unsuspend" 1; done; fi; quit
			mv -f $inactiveacctunsuspended $inactiveacctunsuspended.old
			;;
		esac;;
		*) quit;;
	esac
}



function terminateAcct() {
	echo
	read -n 1 -p "Do you want to TERMINATE all the above accounts? (y/n): " rusure;
	case $rusure in
		y|Y|yes|Yes|YES) echo -e "\n\e[1;31mLET ME ASK YOU THIS ONE MORE TIME.\nARE YOU SURE YOU WANT TO TERMINATE ALL THE ABOVE ACCOUNTS? IF YOU ARE SURE, TYPE 'yes'\e[0m"
		read rusuredc
		case $rusuredc in
			yes) for var in /var/cpanel/suspended/*; do [[ $(echo $var | grep ".lock$") ]] && continue || ( ! [[ $(grep "cpInactiveAcct.sh" $var) ]] && continue || user=$(echo $var | awk -F/ '{print $(NF)}'); echo "Simulating: /scripts/killacct --force $user" ); done
			mv -f $inactiveacctsuspended $inactiveacctsuspended.old 2>/dev/null
			echo -e "\n\e[1;31mTesting mode. NO account has been actually terminated. For real termination edit \"terminateAcct\" function in this script.\e[0m"
			;;
		esac;;
		*) quit;;
	esac
}



function terminateOldAcct() {
	echo
	read -n 1 -p "Do you want to TERMINATE all the accounts that have been suspended 3 months ago? (y/n): " rusure;
	case $rusure in
		y|Y|yes|Yes|YES) echo -e "\n\e[1;31mLET ME ASK YOU THIS ONE MORE TIME.\nARE YOU SURE YOU WANT TO TERMINATE ALL SUSPENDED ACCOUNTS THAT HAVE BEEN SUSPENDED IN 3 MONTHS AGO OR EARLIER? IF YOU ARE SURE, TYPE 'yes'\e[0m"
		read rusuredc
		case $rusuredc in
			yes) unset user; for var in /var/cpanel/suspended/*; do [[ $(echo $var | grep ".lock$") ]] && continue || user=$(echo $var | awk -F/ '{print $(NF)}'); echo "/scripts/killacct --force $user"; done
			echo -e "\n\e[1;31mTesting mode. NO account has actually been terminated. Contact Guy.\e[0m"
			;;
			*) quit;;
		esac;;
		*) quit;;
	esac
}


function quit() {
	#cleanning temp files
	rm -f \
	$localips \
	$skipdomfile \
	$usrdns

	if [[ -s $inactiveacctsuspended ]] && [[ $(cat $inactiveacctunsuspended | wc -l) -le 1 ]]; then mv -f $inactiveacctunsuspended $inactiveacctunsuspended.old; fi
	[[ -s $inactiveacctsuspended ]] && mv -f $inactiveacctsuspended $inactiveacctsuspended.old
	echo; exit
}



function main() {
	echo -e "\nPlease be patient, This may take a while.\n\n"
	curdomips=~/cpinactiveacct/cpinactiveacct-curdomips

	for i in $(seq 0 $((skipdomnum-1)))
	do
			echo "${skipdomain[$i]}" >>$skipdomfile
			((++i))
	done

	echo
	accinfoheaders >$activeacct
	accinfoheaders >$inactiveacctunsuspended
	accinfoheaders >$inactiveacctsuspended

	for curacct in /var/cpanel/users/$accexp
	do
		curusr=$(echo $curacct | cut -d / -f 5)
		if [[ $curusr == "system" ]] || [[ $(echo $curusr | grep ".bak$") ]] || [[ "$(( $(date +%s)-$(grep STARTDATE $curacct | cut -d= -f 2) ))" -lt "5184000" ]] || [[ "$(stat --printf=%g $curacct)" -eq "0" ]]; then continue; fi
		procacctnum=$((++procaccnum))
		usrdns=~/cpinactiveacct/curacct/$curusr; cat $curacct | grep -i ^dns| cut -d = -f 2 >$usrdns

		while read curskipdom
		do
				sed -i /$curskipdom/d $usrdns 2>/dev/null
		done <$skipdomfile

		while read curdom
		do
			echo -n "Checking $curusr | $curdom... "
			curdomactive=0
			dig @8.8.8.8 +short $curdom >$curdomips
			dig @8.8.8.8 +short mx $curdom | awk '{print $2}' | rev | cut -d'.' -f 2- | rev | xargs dig +short >>$curdomips
#               dig @8.8.8.8 +short ns $curdom | rev | cut -d'.' -f 2- | rev | xargs dig +short >>$curdomips # ns record check
			sort $curdomips | uniq >$curdomips.uniq; mv -f $curdomips.uniq $curdomips
			while read curlocalip
			do
				while read curdomip
				do
					if [[ "$curlocalip" == "$curdomip" ]]; then
							activeflag=1
							accinfo >>$activeacct
							echo -e "\e[1;32mACTIVE\e[0m"
							curdomactive=1; ((actaccnum+=1))
							break 3
					fi
				done <$curdomips
			done <$localips
		done <$usrdns
		if [[ $curdomactive == 0 ]]; then
			activeflag=0
			if [[ $(ls -l /var/cpanel/suspended | awk '{print $(NF)}' | grep "^$curusr$") ]]; then {
				accinfo >>$inactiveacctsuspended
				echo -e "\e[96mINACTIVE - ALREADY SUSPENDED\e[0m"
			} else {
				accinfo >>$inactiveacctunsuspended
				echo -e "\e[1;31mINACTIVE\e[0m"
				((inactaccunsuspendednum+=1))
			}
			fi

		fi
	done



	echo

	if [[ $(cat $activeacct | wc -l) -gt 1 ]]; then {
		echo -e "\e[93mActive list ($activeacct):\e[0m"
		cat $activeacct
	} else {
		echo -e "\e[93mNo active accounts have been found.\e[0m"
	}
	fi

	echo -e "\n\n"



	if [[ $(cat $inactiveacctunsuspended | wc -l) -gt 1 ]]; then {
		echo -e "\n\n\e[93mInactive (currently NOT suspended) list ($inactiveacctunsuspended):\e[0m"
		cat $inactiveacctunsuspended
	} else {
		echo -e "\e[93mNo inactive accounts (currently NOT suspended) have been found.\e[0m"
	}
	fi
	
	echo -e "\n\n"
	
	echo -e "\n\n\n\n======================================================================================================================"
	echo "This server contain $(ls -l /var/cpanel/users | tail -n +2 | awk '{print $(NF)}' | grep -v '^system$\|.bak' | wc -l) accounts"
	printf "Account expression: $accexp\n"
	echo Accounts proccessed: $procacctnum
	echo Accounts active: $actaccnum
	echo Accounts previously suspended using this script: $inactaccspendednum
	echo Accounts inactive currently NOT suspended: $inactaccunsuspendednum
	echo -n "(sub)Domain(s) strings skipped: $skipdomnum"
	if [[ $skipdomnum != 0 ]]; then
		while read curskipdom
		do
			echo -e "\e[1;31m $curskipdom\e[0m"
		done <$skipdomfile
	fi
	echo
	[[ $skipsizecheck = 0 ]] && echo "Cumulative size of inactive accounts: (files + db): $((cumsize/1024)) MB"
	echo
	echo See above logs for more detailed report.
	echo Before taking any action it is advised to double check the output, especially if using  \'skipdomain\' option.
	echo; echo
	[[ $inactaccunsuspendednum != 0 ]] && suspendAcct
	quit
}


function mainMenu() {
	cat <<'QUESTION'


	  1. (Re)scan the server for inactive account
	  2. Suspend accounts from previous run
	  3. Terminate accounts from previous runs
	  4. Terminate accounts that are suspended for more than 3 months
	  *. Quit
QUESTION
	read -n 1 -p "Choose your action: " userchoice;
	case $userchoice in
		1) main;;
		2) if [[ -s $inactiveacctunsuspended ]] && [[ $(cat $inactiveacctunsuspended | wc -l) -gt 1 ]]; then {
				echo -e "\n\e[93mprevious inactive currently NOT suspended log has been found:\e[0m"; echo "$inactiveacctunsuspended ($(stat $inactiveacctunsuspended | grep Modify))"
				echo inactive NOT suspended log content:; cat $inactiveacctunsuspended;	echo -e "\nWhat do you want to do?"
				suspendAcct
				} else {
					echo -e "\n\e[93mNo log is available from previous run.\e[0m"
					mainMenu
				}
				fi
				;;
		3) sushist=0; for var in /var/cpanel/suspended/*; do [[ $(echo $var | grep ".lock$") ]] && continue; [[ $sushist -eq 1 ]] && break; [[ $(grep "cpInactiveAcct.sh" $var) ]] && sushist=1; done;
				if [[ $sushist -eq 1 ]]; then {
					echo -e "\n\e[93mprevious inactive ALREADY suspended account(s) has been found:\e[0m"
					echo -e "Inactive accounts previously suspended using this script:\n"
					[[ $skipsizecheck = 0 ]] && echo "Calculating disk usage of the accounts. This may take a moment..."
					prevsusS=0;
					for var in /var/cpanel/suspended/*
					do
						if [[ $(echo $var | grep ".lock$") ]]; then {
							continue
						} else {
							[[ $(grep "cpInactiveAcct.sh" $var) ]] && user=$(echo $var | awk -F/ '{print $(NF)}') || continue
							tabs=$((12-$(printf "$user" | wc -c)))
							if [[ $skipsizecheck = 1 ]]; then {
								printf "User: $user%$((12-$(printf "$user" | wc -c))).sComment: $(cat $var)%$((21-$(wc -c $var | awk '{print $1}'))).shost(s): $(egrep DNS /var/cpanel/users/$user | awk -F= '{print $2}' | tr '\n' ' ')"
							} else {
								acctSize $user; prevsusS=$((prevsusS+sumS))
								sizeMB=$((sumS/1024))
								printf "User: $user%$((12-$(printf "$user" | wc -c))).sSize: $sizeMB MB%$((7-$(printf $sizeMB | wc -c))).sComment: $(cat $var)%$((21-$(wc -c $var | awk '{print $1}'))).shost(s): $(egrep DNS /var/cpanel/users/$user | awk -F= '{print $2}' | tr '\n' ' ')"
								}
							fi
						}
						fi
						echo
					done
					[[ $skipsizecheck = 0 ]] && echo -e "\nAll previous suspended accounts disk usage: $(($prevsusS/1024)) MB\n\n"
					terminateAcct
				} else {
					echo -e "\n\e[93mThis script never suspended accounts in this server.\e[0m"
					mainMenu
				}
				fi
			;;
		4) if [[ $(ls -l /var/cpanel/suspendinfo | tail -n +2 | wc -l) -gt 0 ]]; then {
				sushist=1
				prevsusS=0;
				unset user
				for var in /var/cpanel/suspendinfo/*
				do
					user=$(echo $var | awk -F/ '{print $(NF)}')
					if [[ "$(($(date +%s)-$(grep SUSPENDTIME /var/cpanel/users/$user | cut -d= -f2)))" -lt "7776000" ]]; then sushist=0; fi
				done
				if [[ $sushist -eq 1 ]]; then {
					echo -e "\n\e[93mprevious accounts that have been suspended which are older than 3 months has been found:\e[0m\n"
					[[ $skipsizecheck = 0 ]] && echo -e "Calculating disk usage of the accounts. This may take a moment...\n\n"
					unset user; for var in /var/cpanel/suspendinfo/*
					do
						user=$(echo $var | awk -F/ '{print $(NF)}')
						if [[ "$(($(date +%s)-$(grep SUSPENDTIME /var/cpanel/users/$user | cut -d= -f2)))" -gt "7776000" ]]; then {
							timeOfSus=$((($(date +%s)-$(grep SUSPENDTIME /var/cpanel/users/hbiz | cut -d= -f2))/60/60/24))
							susString=$(printf "Suspended $timeOfSus days ago")
							if [[ $skipsizecheck = 1 ]]; then {
								printf "User: $user%$((12-$(printf "$user" | wc -c))).sComment: $(cat /var/cpanel/suspended/$user)%$((21-$(wc -c /var/cpanel/suspended/$user | awk '{print $1}'))).s$susString%$((26-$(printf "$susString" | wc -c))).shost(s): $(egrep DNS /var/cpanel/users/$user | awk -F= '{print $2}' | tr '\n' ' ')\n"
							} else {
								acctSize $user; prevsusS=$((prevsusS+sumS))
								sizeMB=$((sumS/1024))
								printf "User: $user%$((12-$(printf "$user" | wc -c))).sSize: $sizeMB MB%$((7-$(printf $sizeMB | wc -c))).sComment: $(cat /var/cpanel/suspended/$user)%$((21-$(wc -c /var/cpanel/suspended/$user | awk '{print $1}'))).s$susString%$((26-$(printf "$susString" | wc -c))).shost(s): $(egrep DNS /var/cpanel/users/$user | awk -F= '{print $2}' | tr '\n' ' ')\n"
							}
							fi
						} else {
							echo -e "\n\e[93m\nThere are no suspended account that have been suspended which are older than 3 months.\e[0m"
							mainMenu
						}
						fi
					done
					[[ $skipsizecheck = 0 ]] && echo -e "\nAll previous suspended accounts that are older than 3 months disk usage: $((prevsusS/1024)) MB\n\n"
						terminateOldAcct
				} else {
					echo -e "\n\e[93m\nThere are no suspended account that have been suspended which are older than 3 months.\e[0m"
					mainMenu
				}
				fi
			} else {
				echo -e "\n\e[93m\nThere are no suspended account that have been suspended which are older than 3 months.\e[0m"
				mainMenu
			}
			fi
			;;
		*) echo; quit;;
	esac
}

mainMenu
