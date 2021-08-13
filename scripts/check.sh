#!/bin/bash

MAIL_FROM="MHAreply@innogrid.com"
MAIL_TO="tjkong@innogrid.com"
MASTER_IP=$(/usr/local/bin/masterha_check_status --conf=/etc/mha.cnf | cut -d ',' -f 2 | cut -d ':' -f 2 | sed 's/NOT_RUNNING)./MHA Down/g')
SERVERS=("10.0.8.2" "10.0.8.3" "10.0.8.6")
TIME=$(date +"%F %H:%M:%S")
DB_PORT="63306"
DB_ID="mha"
DB_PASSWD="mha1122"


# Send mail to manager, if server or replication is error
MAILTO_MANAGER_DB_IS_ERROR() {
        STATUS=$1
        SERVER_IP=$2
        RETURN_STATUS=$3
if [ "$STATUS" == "SERVER" ]; then
        echo "[SERVER ERROR] ${SERVER_IP} is error(dead)" > /mha/server_${SERVER_IP}.err
        if [ "$RETURN_STATUS" == "1" ]; then
                SUBJ="[ERROR] SERVER or Daemon error"
                ERROR="Can not connected to DB, Maybe DB is down!!!"
        else
                SUBJ="[ERROR] Unknown Error"
                ERROR="DB Unknown error, please check server"
        fi
elif [ "$STATUS" == "REPLICATION" ]; then
        echo "[REPLICATION ERROR] ${SERVER_IP} replication is error" > /mha/slave_rep_${SERVER_IP}.err
        SUBJ="[ERROR] Replication error"
        ERROR="The status of Replication is STOP, Replication error!!!"
fi
MAIL_BODY=`cat << EOB
=====================================\n
Error server ip : ${SERVER_IP}\n
Master DB ip : ${MASTER_IP}\n
Message : ${ERROR}\n
Time : ${TIME}\n
=====================================\n
Please, check Error server\n
EOB`
         echo -e ${MAIL_BODY} | mail -r ${MAIL_FROM} -s "${SUBJ}" ${MAIL_TO} 
}

# Send mail to manager, if server or replicatio turn to normal.

MAILTO_MANAGER_DB_IS_NORMAL() {
        STATUS=$1
        SERVER_IP=$2    
if [ "$STATUS" == "SERVER" ]; then 
        rm /mha/server_${SERVER_IP}.err
        SUBJ="SERVER or Daemon recovered"
        NORMAL="Server or Daemon has been recovered"
elif [ "$STATUS" == "REPLICATION" ]; then
        rm /mha/slave_rep_${SERVER_IP}.err
        SUBJ="Replication recovered"
        NORMAL="Replication status has been recovered"
fi
MAIL_BODY=`cat << EOB
=====================================\n
Recover server ip : ${SERVER_IP}\n
Master DB ip : ${MASTER_IP}\n
Message : ${NORMAL}\n
Time : ${TIME}\n
=====================================\n
Error recover ended\n
EOB`
         echo -e ${MAIL_BODY} | mail -r ${MAIL_FROM} -s "${SUBJ}" ${MAIL_TO} 
}

# check server status using DB command. 

for serv in ${SERVERS[@]}; do
        SERVER_ERROR_FILE="/mha/server_${serv}.err"
        DB=$(mysql -u${DB_ID} -p${DB_PASSWD} -h ${serv} -P ${DB_PORT} -e "show databases;" 2>&1 )
        DB_STATUS=$?
        if [ "${DB_STATUS}" == "1" ]; then
                if [ ! -e ${SERVER_ERROR_FILE} ]; then
                        MAILTO_MANAGER_DB_IS_ERROR "SERVER" ${serv} ${DB_STATUS}
                        #echo "DB error"
                fi
        elif [ "${DB_STATUS}" == "0" ]; then
                if [ -e ${SERVER_ERROR_FILE} ]; then
                        MAILTO_MANAGER_DB_IS_NORMAL "SERVER" ${serv} 
                        #echo "DB normal"
                fi
        else
                if [ ! -e ${SERVER_ERROR_FILE} ]; then
                        MAILTO_MANAGER_DB_IS_ERROR "SERVER" ${serv} ${DB_STATUS}
                        #echo "DB unknown"
                fi
        fi
done

# If server remains only one or dead all, exit this script 
# No need to check replication. because server is only one or zero.

SERV_LEN=${#SERVERS[@]}
ERRSERV_LEN=$(ls -l /mha/ | grep server_ | wc -l)
NORMAL_SERV=$((${SERV_LEN} - ${ERRSERV_LEN}))
if [ "${NORMAL_SERV}" -le "1" ]; then
        exit 0
fi

# check replication status.
for serv in ${SERVERS[@]}; do
        SLAREPERR_FILE="/mha/slave_rep_${serv}.err"
        SLAVE=$(mysql -u${DB_ID} -p${DB_PASSWD} -P ${DB_PORT} -h ${serv} -e "show slave status\G" 2>&1 | grep Slave_IO_Running | awk '{print $2}')
        if [ -n "${SLAVE}" ]; then
                if [ "${SLAVE}" == "Yes" ]; then
                        if [ -e ${SLAREPERR_FILE} ]; then
                                MAILTO_MANAGER_DB_IS_NORMAL "REPLICATION" ${serv}
                                #echo "slave = Yes"
                        fi
                else    
                        if [ ! -e ${SLAREPERR_FILE} ]; then
                                MAILTO_MANAGER_DB_IS_ERROR "REPLICATION" ${serv}
                                #echo "slave = no"
                        fi
                fi
        fi
done
