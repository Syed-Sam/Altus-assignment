# The format of an email address is local-part@domain.
# There are certain mail systems compliant with RFC standard of the email address and could be found in rfc5322, rfc6854, etc.
#
# However, it is hard to escape all the special characters in the bash
# so, in this script, it will only check the address syntax against the 
# regex search pattern and print the expected results.
#

function isEmailValid() {
    regex="^([A-Za-z]+[A-Za-z0-9]*((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*){1,})@(([A-Za-z]+[A-Za-z0-9]*)+((\.|\-|\_)?([A-Za-z]+[A-Za-z0-9]*)+){1,})+\.([A-Za-z]{2,})+"
    [[ "${1}" =~ $regex ]]
}
filename=$1
count=1
cat $filename | awk -F '\n' '{print $0}' | while IFS= read -r row
do
    if isEmailValid ${row} ;then
	  echo -e "$row"; printf " %-48s \e[32m[Email is VALID]\e[m\n"
    else
          echo -e "$row"; printf " %-48s \e[31m[Email is INVALID]\e[m\n"
    fi
    count=$(($count+1))
done
