#!/bin/bash

#####################################################
#          функции обновления базы asterisk         #
##################################################### 

updateMysql(){
echo "updateMysql 1=$1 2=$2"
local startId=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT $2 FROM $1 ORDER BY $2 ASC LIMIT 1";)
local endId=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT $2 FROM $1 ORDER BY $2 DESC LIMIT 1";)
local masterId=$(grep $1 /tmp/mergeServers/masterServer/uniqueId.txt | cut -f2 -d' ')
local checknumberAdd=$(($masterId+1-$startId))
if [ $checknumberAdd -le $endId ] && [ $checknumberAdd -gt 0 ];then
  local numberAdd=$(($checknumberAdd+$endId))
  local numberDel=$endId
  echo "$1 $numberAdd $numberDel" >> /tmp/mergeServers/shiftValues.txt
else
  local numberAdd=$checknumberAdd
  local numberDel=0
  echo "$1 $numberAdd $numberDel" >> /tmp/mergeServers/shiftValues.txt
fi
mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 + $numberAdd";
if [ $numberDel -ne 0 ];then
  mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 - $numberDel";
fi
}


updateMysqlQueuesAndRingGroups(){
echo "updateMysqlQueuesAndRingGroups"
#Ищем те очереди на slave которые не пересекаются с master и добавляем их в список master
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension FROM queues_config WHERE extension like '6%'" >> /tmp/mergeServers/tmp/tmpQueues6XXX.txt
sed -i 's/^/queues /' /tmp/mergeServers/tmp/tmpQueues6XXX.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT grpnum FROM ringgroups WHERE grpnum like '6%'" >> /tmp/mergeServers/tmp/tmpRingGroup6XXX.txt
sed -i 's/^/ringgroups /' /tmp/mergeServers/tmp/tmpRingGroup6XXX.txt
cat /tmp/mergeServers/tmp/tmpQueues6XXX.txt /tmp/mergeServers/tmp/tmpRingGroup6XXX.txt > /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt
checkDoubleNum=$(cat /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt | cut -f2 -d' ' | uniq -d)
if [ -n "$checkAnomaly" ];then
  echo "+++++++++++++++++++++++++++++"
  cat /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt | cut -f2 -d' ' | uniq -d
  echo "нашел дубли или и лечи так же правь файлы, мне лень, я ленивый скрипт"
  read -p "Нажмите ENTER для продолжения, больше проверок не будет"
fi
queuesVol=$(cat /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt | wc -l)
cp /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt /tmp/mergeServers/update/slaveQueues6XXX.txt
cp /tmp/mergeServers/masterServer/queues6XXX.txt /tmp/mergeServers/update/masterQueues6XXX.txt
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
checkExistQeue=''
tableName=$(cat /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt | cut -f1 -d' ' | sed -n "$numStr"p)
queueNum=$(cat /tmp/mergeServers/slaveServer/queuesRingGroup6XXX.txt | cut -f2 -d' ' | sed -n "$numStr"p)
checkExistQeue=$(grep ^"$queueNum"$ /tmp/mergeServers/masterServer/queues6XXX.txt)
if [ -z "$checkExistQeue" ];then
  sed -i "/.* $queueNum/d"  /tmp/mergeServers/update/slaveQueues6XXX.txt
  echo "$tableName $queueNum $queueNum" >> /tmp/mergeServers/update/tmpUpdateQueues6XXX.txt
  echo "$queueNum" >> /tmp/mergeServers/update/masterQueues6XXX.txt
fi
done

#Составляем список свободных номеров 6ХХХ на master
for ((i=6000; i < 6999; i++))
do
checkFreeQueue=''
checkFreeQueue=$(cut -f2 -d' ' /tmp/mergeServers/update/masterQueues6XXX.txt | grep "$i")
if [ -z "$checkFreeQueue" ];then
  echo "$i" >> /tmp/mergeServers/update/masterFreeQueue6XXX.txt
fi
done

#Добавляем к списку не пересекающихся очередей очереди slave и на какие очереди их нужно сменить
queuesVol=$(cat /tmp/mergeServers/update/slaveQueues6XXX.txt | wc -l)
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
tableName=$(cat /tmp/mergeServers/update/slaveQueues6XXX.txt | cut -f1 -d' ' | sed -n "$numStr"p)
slaveQueueNum=$(cat /tmp/mergeServers/update/slaveQueues6XXX.txt | cut -f2 -d' ' | sed -n "$numStr"p)
masterFreeQueue=$(cat /tmp/mergeServers/update/masterFreeQueue6XXX.txt | sed -n "$numStr"p)
echo "$tableName $slaveQueueNum $masterFreeQueue" >> /tmp/mergeServers/update/tmpUpdateQueues6XXX.txt
done
sort -k2 -t' ' /tmp/mergeServers/update/tmpUpdateQueues6XXX.txt > /tmp/mergeServers/update/updateQueues6XXX.txt

#добавляем 1 перед изменяемым номером очереди 6XXX в таблицах queues_config и queues_details
queuesVol=$(cat /tmp/mergeServers/update/updateQueues6XXX.txt | wc -l)
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
tableName=$(cut -f1 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
slaveQueueNum=$(cut -f2 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
masterFreeQueue=$(cut -f3 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
if [ "$slaveQueueNum" -ne "$masterFreeQueue" ];then
  if [ "$tableName" == "queues" ];then
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE queues_config SET extension=1$slaveQueueNum WHERE extension=$slaveQueueNum"
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE queues_details SET id=1$slaveQueueNum WHERE id=$slaveQueueNum"
  else
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE ringgroups SET grpnum=1$slaveQueueNum WHERE grpnum=$slaveQueueNum"
  fi
fi
done

#обновляем изменяемые очереди queues_config и queues_details и ringgroups
queuesVol=$(cat /tmp/mergeServers/update/updateQueues6XXX.txt | wc -l)
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
tableName=$(cut -f1 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
slaveQueueNum=$(cut -f2 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
masterFreeQueue=$(cut -f3 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
if [ "$slaveQueueNum" -ne "$masterFreeQueue" ];then
  if [ "$tableName" == "queues" ];then
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE queues_config SET extension=$masterFreeQueue WHERE extension=1$slaveQueueNum"
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE queues_details SET id=$masterFreeQueue WHERE id=1$slaveQueueNum"
  else
    mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE ringgroups SET grpnum=$masterFreeQueue WHERE grpnum=1$slaveQueueNum"
  fi
fi
done
}


updateMysqlOtherTables(){
echo "updateMysqlOtherTables 1=$1 2=$2"
mkdir -p /tmp/mergeServers/$1/
#table_name uniqueId parameter_to_change
echo "announcement announcement_id post_dest" > /tmp/mergeServers/$1/announcement-post_dest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT announcement_id, post_dest FROM announcement WHERE post_dest like '$2%'" >> /tmp/mergeServers/$1/announcement-post_dest.txt
echo "incoming id destination" > /tmp/mergeServers/$1/incoming-destination.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, destination FROM incoming WHERE destination like '$2%'" >> /tmp/mergeServers/$1/incoming-destination.txt
echo "ivr_details id invalid_destination" > /tmp/mergeServers/$1/ivr_details-invalid_destination.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, invalid_destination FROM ivr_details WHERE invalid_destination like '$2%'" >> /tmp/mergeServers/$1/ivr_details-invalid_destination.txt
echo "ivr_details id timeout_destination" > /tmp/mergeServers/$1/ivr_details-timeout_destination.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, timeout_destination FROM ivr_details WHERE timeout_destination LIKE '$2%'" >> /tmp/mergeServers/$1/ivr_details-timeout_destination.txt
echo "ivr_entries ivr_id selection dest" > /tmp/mergeServers/$1/ivr_entries-dest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT ivr_id, selection, dest FROM ivr_entries WHERE dest like '$2%'" >> /tmp/mergeServers/$1/ivr_entries-dest.txt
echo "timeconditions timeconditions_id truegoto" > /tmp/mergeServers/$1/timeconditions-truegoto.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT timeconditions_id, truegoto FROM timeconditions WHERE truegoto LIKE '$2%'" >> /tmp/mergeServers/$1/timeconditions-truegoto.txt
echo "timeconditions timeconditions_id falsegoto" > /tmp/mergeServers/$1/timeconditions-falsegoto.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT timeconditions_id, falsegoto FROM timeconditions WHERE falsegoto LIKE '$2%'" >> /tmp/mergeServers/$1/timeconditions-falsegoto.txt
echo "users extension noanswer_dest" > /tmp/mergeServers/$1/users-noanswer_dest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, noanswer_dest FROM users WHERE noanswer_dest like '$2%'" >> /tmp/mergeServers/$1/users-noanswer_dest.txt
echo "users extension busy_dest" > /tmp/mergeServers/$1/users-busy_dest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, busy_dest FROM users WHERE busy_dest like '$2%'" >> /tmp/mergeServers/$1/users-busy_dest.txt
echo "users extension chanunavail_dest" > /tmp/mergeServers/$1/users-chanunavail_dest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, chanunavail_dest FROM users WHERE chanunavail_dest like '$2%'" >> /tmp/mergeServers/$1/users-chanunavail_dest.txt
echo "findmefollow grpnum postdest" > /tmp/mergeServers/$1/findmefollow-postdest.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT grpnum, postdest FROM findmefollow WHERE postdest like '$2%'" >> /tmp/mergeServers/$1/findmefollow-postdest.txt
for ((i=0; i < 11; i++))
do
local numStrI=$(($i + 1))
fileName=$(ls -1 /tmp/mergeServers/$1 | sed -n "$numStrI"p)
strUpdateVol=$(cat /tmp/mergeServers/$1/$fileName | tail -n+2 | wc -l)
  for ((a=1; a <= $strUpdateVol; a++))
  do
  echo "$i from $strUpdateVol $1"
  local numStrA=$(($a + 1))
  if ! [ "$fileName" == "ivr_entries-dest.txt" ];then
    firstId=$(cut -f1 /tmp/mergeServers/$1/$fileName | sed -n "$numStrA"p)
    editParametr=$(cut -f2 /tmp/mergeServers/$1/$fileName | sed -n "$numStrA"p)
  else
    firstId=$(cut -f1 /tmp/mergeServers/$1/$fileName | sed -n "$numStrA"p)
	secondId=$(cut -f2 /tmp/mergeServers/$1/$fileName | sed -n "$numStrA"p)
    editParametr=$(cut -f3 /tmp/mergeServers/$1/$fileName | sed -n "$numStrA"p)
  fi
  case $1 in
  announcement)
    announcementIdOld=$(echo $editParametr | cut -f1 -d',' | cut -f3 -d'-')
	local numberAdd=$(grep announcement /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
	local numberDel=$(grep announcement /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
	local announcementIdNew=$(($announcementIdOld + $numberAdd - $numberDel))
	newParametr=$(echo $2"$announcementIdNew",s,1)
	;;
  ivr_details)
    ivr_detailsIdOld=$(echo $editParametr | cut -f1 -d',' | cut -f2 -d'-')
	local numberAdd=$(grep ivr_details /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
	local numberDel=$(grep ivr_details /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
	local ivr_detailsIdNew=$(($ivr_detailsIdOld + $numberAdd - $numberDel))
	newParametr=$(echo $2"$ivr_detailsIdNew",s,1)
	tableColumn=$(echo $fileName | cut -f2 -d'-' | cut -f1 -d'.')
	;;
  timeconditions)
    timeconditionsIdOld=$(echo $editParametr | cut -f2 -d',')
	local numberAdd=$(grep timeconditions /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
	local numberDel=$(grep timeconditions /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
	local timeconditionsIdNew=$(($timeconditionsIdOld + $numberAdd - $numberDel))
	newParametr=$(echo $2,$timeconditionsIdNew,1)
	;;
  miscdests)
    miscdestsIdOld=$(echo $editParametr | cut -f2 -d',')
	destdial=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT destdial FROM miscdests WHERE id=$miscdestsIdOld")
	checkExistDestdial=$(cat /tmp/mergeServers/masterServer/miscdests.txt | sed 's|\t*| |' | grep " $destdial$" | head -n1 | cut -f1 -d' ')
	if [ -n "$checkExistDestdial" ];then
	  newParametr=$checkExistDestdial
	  delDubleDestdial=$(cat /tmp/mergeServers/masterServer/miscdests.txt | sed 's|\t*| |' | grep " $destdial$" | head -n1 | cut -f2 -d' ')
	  echo "del this miscdest id=$checkExistDestdial num=$delDubleDestdial" >> /tmp/margeServers/delMiscdests.txt
	else
	  local numberAdd=$(grep miscdests /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
	  local numberDel=$(grep miscdests /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
	  local miscdestsIdNew=$(($miscdestsIdOld + $numberAdd - $numberDel))
	  newParametr=$(echo $2,$miscdestsIdNew,1)
	fi
	;;
  queues)
    queueIdOld=$(echo $editParametr | cut -f2 -d',')
	newQueue=$(grep "queues $queueIdOld " /tmp/mergeServers/update/updateQueues6XXX.txt | cut -f3 -d' ')
	if [ -n "$newQueue" ];then
	  newParametr=$(echo $2,$newQueue,1)
	else
	  newParametr=''
	fi
	;;
  pre-queues)
    queueIdOld=$(echo $editParametr | cut -f2 -d',')
	newQueue=$(grep "queues $queueIdOld " /tmp/mergeServers/update/updateQueues6XXX.txt | cut -f3 -d' ')
	if [ -n "$newQueue" ];then
	  newParametr=$(echo $2,$newQueue,1)
	else
	  newParametr=''
	fi
	;;
  ringgroups)
    ringgroupsIdOld=$(echo $editParametr | cut -f2 -d',')
	newRinggroup=$(grep "ringgroups $ringgroupsIdOld " /tmp/mergeServers/update/updateQueues6XXX.txt | cut -f3 -d' ')
	if [ -n "$newRinggroup" ];then
	  newParametr=$(echo $2,$newRinggroup,1)
	else
	  newParametr=''
	fi
	;;
  *)
    echo "in function updateMysqlOtherTables ERROR table_name $1 uniqueId $2"
	;;
  esac
  if [ -n "$newParametr" ];then
  #table_name uniqueId parameter_to_change
    if ! [ "$fileName" == "ivr_entries-dest.txt" ];then
	  tableName=$(cut -f1 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  uniqueIdFirst=$(cut -f2 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  changingParameter=$(cut -f3 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $tableName SET $changingParameter=\"$newParametr\" WHERE $uniqueIdFirst=\"$firstId\" AND $changingParameter=\"$editParametr\" ";
    else
	  tableName=$(cut -f1 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  uniqueIdFirst=$(cut -f2 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  uniqueIdSecond=$(cut -f3 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  changingParameter=$(cut -f4 -d' ' /tmp/mergeServers/$1/$fileName | head -n1)
	  mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $tableName SET $changingParameter=\"$newParametr\" WHERE $uniqueIdFirst=\"$firstId\" AND $uniqueIdSecond=\"$secondId\" AND $changingParameter=\"$editParametr\" ";
	  fi
  else
    echo "newParametr is empty fileName=$fileName, firstId=$firstId, secondId=$secondId, editParametr=$editParametr" >> /tmp/mergeServers/ERRORupdateMysqlOtherTables.txt
  fi
  done
done
}


findAnomalyInOtherTables(){
echo "findAnomalyInOtherTables"
echo "announcement" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT announcement_id, post_dest FROM announcement WHERE post_dest!='' AND post_dest!='app-blackhole,hangup,1' AND post_dest not like 'from-did-direct%' AND post_dest not like 'app-announcement-%' AND post_dest not like 'ivr-%' AND post_dest not like 'ext-miscdests%' AND post_dest not like 'timeconditions%' AND post_dest not like 'ext-queues%' AND post_dest not like 'pre-queue-dial%' AND post_dest not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "incoming" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, destination FROM incoming WHERE destination!='' AND destination!='app-blackhole,hangup,1' AND destination not like 'from-did-direct%' AND destination not like 'app-announcement-%' AND destination not like 'ivr-%' AND destination not like 'ext-miscdests%' AND destination not like 'timeconditions%' AND destination not like 'ext-queues%' AND destination not like 'pre-queue-dial%' AND destination not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "ivr_details invalid_destination" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, invalid_destination FROM ivr_details WHERE invalid_destination!='' AND invalid_destination!='app-blackhole,hangup,1' AND invalid_destination not like 'from-did-direct%' AND invalid_destination not like 'app-announcement-%' AND invalid_destination not like 'ivr-%' AND invalid_destination not like 'ext-miscdests%' AND invalid_destination not like 'timeconditions%' AND invalid_destination not like 'ext-queues%' AND invalid_destination not like 'pre-queue-dial%' AND invalid_destination not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "ivr_details timeout_destination" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, timeout_destination FROM ivr_details WHERE timeout_destination!='' AND timeout_destination!='app-blackhole,hangup,1' AND timeout_destination not like 'from-did-direct%' AND timeout_destination not like 'app-announcement-%' AND timeout_destination not like 'ivr-%' AND timeout_destination not like 'ext-miscdests%' AND timeout_destination not like 'timeconditions%' AND timeout_destination not like 'ext-queues%' AND timeout_destination not like 'pre-queue-dial%' AND timeout_destination not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "ivr_entries" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT ivr_id, selection, dest FROM ivr_entries WHERE dest!='' AND dest!='app-blackhole,hangup,1' AND dest not like 'from-did-direct%' AND dest not like 'app-announcement-%' AND dest not like 'ivr-%' AND dest not like 'ext-miscdests%' AND dest not like 'timeconditions%' AND dest not like 'ext-queues%' AND dest not like 'pre-queue-dial%' AND dest not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "timeconditions truegoto" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT timeconditions_id, truegoto FROM timeconditions WHERE truegoto!='' AND truegoto!='app-blackhole,hangup,1' AND truegoto not like 'from-did-direct%' AND truegoto not like 'app-announcement-%' AND truegoto not like 'ivr-%' AND truegoto not like 'ext-miscdests%' AND truegoto not like 'timeconditions%' AND truegoto not like 'ext-queues%' AND truegoto not like 'pre-queue-dial%' AND truegoto not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "timeconditions falsegoto" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT timeconditions_id, falsegoto FROM timeconditions WHERE falsegoto!='' AND falsegoto!='app-blackhole,hangup,1' AND falsegoto not like 'from-did-direct%' AND falsegoto not like 'app-announcement-%' AND falsegoto not like 'ivr-%' AND falsegoto not like 'ext-miscdests%' AND falsegoto not like 'timeconditions%' AND falsegoto not like 'ext-queues%' AND falsegoto not like 'pre-queue-dial%' AND falsegoto not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "users noanswer_dest" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, noanswer_dest FROM users WHERE noanswer_dest!='' AND noanswer_dest!='app-blackhole,hangup,1' AND noanswer_dest not like 'from-did-direct%' AND noanswer_dest not like 'app-announcement-%' AND noanswer_dest not like 'ivr-%' AND noanswer_dest not like 'ext-miscdests%' AND noanswer_dest not like 'timeconditions%' AND noanswer_dest not like 'ext-queues%' AND noanswer_dest not like 'pre-queue-dial%' AND noanswer_dest not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "users busy_dest" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, busy_dest FROM users WHERE busy_dest!='' AND busy_dest!='app-blackhole,hangup,1' AND busy_dest not like 'from-did-direct%' AND busy_dest not like 'app-announcement-%' AND busy_dest not like 'ivr-%' AND busy_dest not like 'ext-miscdests%' AND busy_dest not like 'timeconditions%' AND busy_dest not like 'ext-queues%' AND busy_dest not like 'pre-queue-dial%' AND busy_dest not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "users chanunavail_dest" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension, chanunavail_dest FROM users WHERE chanunavail_dest!='' AND chanunavail_dest!='app-blackhole,hangup,1' AND chanunavail_dest not like 'from-did-direct%' AND chanunavail_dest not like 'app-announcement-%' AND chanunavail_dest not like 'ivr-%' AND chanunavail_dest not like 'ext-miscdests%' AND chanunavail_dest not like 'timeconditions%' AND chanunavail_dest not like 'ext-queues%' AND chanunavail_dest not like 'pre-queue-dial%' AND chanunavail_dest not like 'ext-group%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
echo "findmefollow postdest" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT grpnum, postdest FROM findmefollow WHERE postdest!='' AND postdest!='app-blackhole,hangup,1' AND postdest not like 'from-did-direct%' AND postdest not like 'app-announcement-%' AND postdest not like 'ivr-%' AND postdest not like 'ext-miscdests%' AND postdest not like 'timeconditions%' AND postdest not like 'ext-queues%' AND postdest not like 'pre-queue-dial%' AND postdest not like 'ext-group%' AND postdest not like 'ext-local%'" >> /tmp/mergeServers/findAnomalyInOtherTables.txt
checkAnomaly=$(cat /tmp/mergeServers/findAnomalyInOtherTables.txt | grep "^[0-9]" | wc -l)
if [ "$checkAnomaly" -ne 0 ];then
  echo "+++++++++++++++++++++++++++++"
  cat /tmp/mergeServers/findAnomalyInOtherTables.txt
  echo "Нашел аномалии, поправь их самостоятельно"
  read -p "Нажмите ENTER для продолжения"
fi
}


updateMysqlSubtable(){
echo "updateMysqlSubtable 1=$1 2=$2 3=$3"
local numberAdd=$(grep $3 /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
local numberDel=$(grep $3 /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 + $numberAdd";
if [ $numberDel -ne 0 ];then
  mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 - $numberDel";
fi
}


updateMysqlRecordingsSubtable(){
echo "updateMysqlRecordingsSubtable 1=$1 2=$2"
local numberAdd=$(grep recordings /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
local numberDel=$(grep recordings /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 + $numberAdd WHERE $2!='0' OR $2!='NULL'";
if [ $numberDel -ne 0 ];then
  mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE $1 SET $2=$2 - $numberDel WHERE $2!='0' OR $2!='NULL'";
fi
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT $2 FROM $1 WHERE $2!='0' OR $2!='NULL'" >> /tmp/mergeServers/tmpUsedRecordings.txt
}


cpUsedRecordings(){
echo "cpUsedRecordings"
sort /tmp/mergeServers/tmpUsedRecordings.txt | uniq > /tmp/mergeServers/usedRecordings.txt
usedRecordingsVol=$(cat /tmp/mergeServers/usedRecordings.txt | wc -l)
for ((i=0; i < $usedRecordingsVol; i++))
do
local numStr=$(($i + 1))
echo "$i from $usedRecordingsVol"
recordID=$(cat /tmp/mergeServers/usedRecordings.txt | sed -n "$numStr"p)
fileName=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT filename FROM recordings WHERE id=$recordID")
if [ -f /var/lib/asterisk/sounds/ru/"$fileName" ] || [ -f /var/lib/asterisk/sounds/ru/"$fileName".wav ];then
  cp /var/lib/asterisk/sounds/ru/"$fileName"* /tmp/mergeServers/sounds/
else
  echo "Not found file recordID $recordID fileName $fileName"
fi
done
}


makeCusromDestinations(){
echo "makeCusromDestinations"
mysql -uroot -p$pass -D asterisk -N -B -e "INSERT INTO kvstore (module, \`key\`, val, \`type\`, id) VALUES ('FreePBX\\\\modules\\\\Customappsreg',\"$num\",'{\"destid\":\"$num\",\"target\":\"pre-queue-dial,$preQueue,1\",\"description\":\"pre-queue-dial-$preQueue\",\"notes\":\"\",\"destret\":\"0\",\"dest\":null}','json-arr','dests')";

mysql -uroot -p$pass -D asterisk -N -B -e "UPDATE kvstore SET val=46 WHERE module like '%Customappsreg%' and \`key\`='currentid'"


for ((i=1; i<=30; i++))
do
num=$(($i + 26))
preQueue=$(cut -f2 -d',' /tmp/1.txt | sed -n "$i"p)
echo "INSERT INTO kvstore (module, \`key\`, val, \`type\`, id) VALUES ('FreePBX\\\\modules\\\\Customappsreg',\"$num\",'{\"destid\":\"$num\",\"target\":\"pre-queue-dial,$preQueue,1\",\"description\":\"pre-queue-dial-$preQueue\",\"notes\":\"\",\"destret\":\"0\",\"dest\":null}','json-arr','dests');"
done


}


#####################################################
#          функции обновления базы cc-kontur        #
##################################################### 

updateMysqlKontur(){
echo "updateMysqlKontur 1=$1 2=$2"
local startId=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT $2 FROM $1 ORDER BY $2 ASC LIMIT 1";)
if [ -z $startId ];then startId=0;fi
local endId=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT $2 FROM $1 ORDER BY $2 DESC LIMIT 1";)
if [ -z $endId ];then endId=0;fi
local masterId=$(grep "kontur_$1 " /tmp/mergeServers/masterServer/uniqueId.txt | cut -f2 -d' ')
if [ "$masterId" == "kontur_$1" ];then masterId=0;fi
local checknumberAdd=$(($masterId+1-$startId))
if [ $checknumberAdd -le $endId ] && [ $checknumberAdd -gt 0 ];then
  local numberAdd=$(($checknumberAdd+$endId))
  local numberDel=$endId
  echo "kontur_$1 $numberAdd $numberDel" >> /tmp/mergeServers/shiftValues.txt
else
  local numberAdd=$checknumberAdd
  local numberDel=0
  echo "kontur_$1 $numberAdd $numberDel" >> /tmp/mergeServers/shiftValues.txt
fi
mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE $1 SET $2=$2 + $numberAdd";
if [ $numberDel -ne 0 ];then
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE $1 SET $2=$2 - $numberDel";
fi
}

updateMysqlQueuesKontur(){
echo "updateMysqlQueuesKontur"
#добавляем 1 перед изменяемым номером очереди 6XXX в таблицах queues_config и queues_details
queuesVol=$(cat /tmp/mergeServers/update/updateQueues6XXX.txt | wc -l)
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
tableName=$(cut -f1 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
slaveQueueNum=$(cut -f2 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
masterFreeQueue=$(cut -f3 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
if [ "$slaveQueueNum" -ne "$masterFreeQueue" ] && [ "$tableName" == "queues" ];then
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE queues SET id=1$slaveQueueNum WHERE id=$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE queues_agents SET queue_id=1$slaveQueueNum WHERE queue_id=$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE cdr_agents SET queue_id=1$slaveQueueNum WHERE queue_id=$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE cdr_queues SET queue_id=1$slaveQueueNum WHERE queue_id=$slaveQueueNum"
fi
done
#обновляем изменяемые очереди
queuesVol=$(cat /tmp/mergeServers/update/updateQueues6XXX.txt | wc -l)
for ((i=0; i < $queuesVol; i++))
do
echo "$i from $queuesVol"
local numStr=$(($i + 1))
tableName=$(cut -f1 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
slaveQueueNum=$(cut -f2 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
masterFreeQueue=$(cut -f3 -d' ' /tmp/mergeServers/update/updateQueues6XXX.txt | sed -n "$numStr"p)
if [ "$slaveQueueNum" -ne "$masterFreeQueue" ] && [ "$tableName" == "queues" ];then
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE queues SET id=$masterFreeQueue WHERE id=1$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE queues_agents SET queue_id=$masterFreeQueue WHERE queue_id=1$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE cdr_agents SET queue_id=1$slaveQueueNum WHERE queue_id=$slaveQueueNum"
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE cdr_queues SET queue_id=$masterFreeQueue WHERE queue_id=1$slaveQueueNum"
fi
done
}

updateMysqlSubtableKontur(){
echo "updateMysqlSubtableKontur 1=$1 2=$2 3=$3"
local numberAdd=$(grep $3 /tmp/mergeServers/shiftValues.txt | cut -f2 -d' ')
local numberDel=$(grep $3 /tmp/mergeServers/shiftValues.txt | cut -f3 -d' ')
mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE $1 SET $2=$2 + $numberAdd";
if [ $numberDel -ne 0 ];then
  mysql -uroot -p$pass -D cc-kontur -N -B -e "UPDATE $1 SET $2=$2 - $numberDel";
fi
}

#######################################################
#######################################################
##  конец области функций, начало исполняемого кода  ##
#######################################################
#######################################################

#протестировать что если таблица пуста то он нормально отработает
pass=$(grep "DBASTPASS=" /home/monitoring/mysql-bacula.sh | cut -f2 -d"'")
if [[ "$pass" == "PASSWORD" || -z $pass ]];then
  echo "no_pass in /home/monitoring/mysql-bacula.sh"
  exit
fi

#backup base asterisk and conf file
mkdir -p /tmp/mergeServers/masterServer/
mkdir /tmp/mergeServers/update/
mkdir /tmp/mergeServers/tmp/
mkdir /tmp/mergeServers/slaveServer
mkdir /tmp/mergeServers/sounds/
#sip
echo "asterisk -rx 'sip show peers'" > /tmp/mergeServers/asterisk.sip_peers.txt
asterisk -rx 'sip show peers' >> /tmp/mergeServers/asterisk.sip_peers.txt
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> /tmp/mergeServers/asterisk.sip_peers.txt
echo "asterisk -rx 'sip show registry'" >> /tmp/mergeServers/asterisk.sip_peers.txt
asterisk -rx 'sip show registry' >> /tmp/mergeServers/asterisk.sip_peers.txt
#pjsip
echo "asterisk -rx 'pjsip show endpoints'" > /tmp/mergeServers/asterisk.pjsip_peers.txt
asterisk -rx 'pjsip show endpoints' >> /tmp/mergeServers/asterisk.pjsip_peers.txt
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> /tmp/mergeServers/asterisk.pjsip_peers.txt
echo "asterisk -rx 'pjsip show registrations'" >> /tmp/mergeServers/asterisk.pjsip_peers.txt
asterisk -rx 'pjsip show registrations' >> /tmp/mergeServers/asterisk.pjsip_peers.txt
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> /tmp/mergeServers/asterisk.pjsip_peers.txt
echo "asterisk -rx 'pjsip show contacts'" >> /tmp/mergeServers/asterisk.pjsip_peers.txt
asterisk -rx 'pjsip show contacts' >> /tmp/mergeServers/asterisk.pjsip_peers.txt
#mysqldump -uroot -p$pass asterisk > /tmp/mergeServers/asterisk.sql
#mysqldump -uroot -p$pass cc-kontur > /tmp/mergeServers/cc-kontur.sql

#check bulkhandler
#checkBulkhandler=$(fwconsole ma list | grep bulkhandler)
#if [ -z "$checkBulkhandler" ];then
#  fwconsole ma downloadinstall bulkhandler
#fi


#выполнить запросы на id нужных таблиц в базах asterisk  и cc-kontur
#запрос на mp5
echo "Скрипт для выполнения мержа"
echo "Выполни эти комманды на удаленном сервере"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
cat << "EOF"
mkdir /tmp/mergeServers/
> /tmp/mergeServers/uniqueId.txt
> /tmp/mergeServers/queues6XXX.txt
> /tmp/mergeServers/miscdests.txt
pass=$(grep "DBASTPASS=" /home/monitoring/mysql-bacula.sh | cut -f2 -d"'")
announcement=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT announcement_id FROM announcement ORDER BY announcement_id DESC LIMIT 1";)
echo "announcement $announcement" >> /tmp/mergeServers/uniqueId.txt
incoming=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM incoming ORDER BY id DESC LIMIT 1";)
echo "incoming $incoming" >> /tmp/mergeServers/uniqueId.txt
ivr_details=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM ivr_details ORDER BY id DESC LIMIT 1";)
echo "ivr_details $ivr_details" >> /tmp/mergeServers/uniqueId.txt
miscdests=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM miscdests ORDER BY id DESC LIMIT 1";)
echo "miscdests $miscdests" >> /tmp/mergeServers/uniqueId.txt
outbound_routes=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT route_id FROM outbound_routes ORDER BY route_id DESC LIMIT 1";)
echo "outbound_routes $outbound_routes" >> /tmp/mergeServers/uniqueId.txt
recordings=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM recordings ORDER BY id DESC LIMIT 1";)
echo "recordings $recordings" >> /tmp/mergeServers/uniqueId.txt
timeconditions=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT timeconditions_id FROM timeconditions ORDER BY timeconditions_id DESC LIMIT 1";)
echo "timeconditions $timeconditions" >> /tmp/mergeServers/uniqueId.txt
timegroups_groups=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM timegroups_groups ORDER BY id DESC LIMIT 1";)
echo "timegroups_groups $timegroups_groups" >> /tmp/mergeServers/uniqueId.txt
timegroups_details=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id FROM timegroups_details ORDER BY id DESC LIMIT 1";)
echo "timegroups_details $timegroups_details" >> /tmp/mergeServers/uniqueId.txt
trunks=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT trunkid FROM trunks ORDER BY trunkid DESC LIMIT 1";)
echo "trunks $trunks" >> /tmp/mergeServers/uniqueId.txt
customDest=$(mysql -uroot -p$pass -D asterisk -N -B -e "SELECT val FROM kvstore WHERE module like '%Customappsreg%' and \`key\`='currentid'")
echo "customDest $customDest" >> /tmp/mergeServers/uniqueId.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT extension FROM queues_config WHERE extension like '6%'" >> /tmp/mergeServers/tmp_queues6XXX.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT grpnum FROM ringgroups WHERE grpnum like '6%'" >> /tmp/mergeServers/tmp_queues6XXX.txt
sort /tmp/mergeServers/tmp_queues6XXX.txt | uniq > /tmp/mergeServers/queues6XXX.txt
mysql -uroot -p$pass -D asterisk -N -B -e "SELECT id, destdial FROM miscdests ORDER BY id ASC" >> /tmp/mergeServers/miscdests.txt
#kontur
kontur_agents=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM agents ORDER BY id DESC LIMIT 1";)
echo "kontur_agents $kontur_agents" >> /tmp/mergeServers/uniqueId.txt
#kontur_cdr
kontur_actions_log=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM actions_log ORDER BY id DESC LIMIT 1";)
echo "kontur_actions_log $kontur_actions_log" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr $kontur_cdr" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_agents=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_agents ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_agents $kontur_cdr_agents" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_cdr=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_cdr ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_cdr $kontur_cdr_cdr" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_dialer=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_dialer ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_dialer $kontur_cdr_dialer" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_dialout=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_dialout ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_dialout $kontur_cdr_dialout" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_direct=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_direct ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_direct $kontur_cdr_direct" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_events=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_events ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_events $kontur_cdr_events" >> /tmp/mergeServers/uniqueId.txt
kontur_cdr_queues=$(mysql -uroot -p$pass -D cc-kontur -N -B -e "SELECT id FROM cdr_queues ORDER BY id DESC LIMIT 1";)
echo "kontur_cdr_queues $kontur_cdr_queues" >> /tmp/mergeServers/uniqueId.txt
EOF
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

read -p "Как все будет сделано нажмите ENTER для продолжения"

x=0
while [ $x == 0 ]
do
echo "Файлы /tmp/mergeServers/uniqueId.txt /tmp/mergeServers/queues6XXX.txt /tmp/mergeServers/miscdests.txt"
echo "скопируй указанные файлы в папку /tmp/mergeServers/masterServer/"
read -p "Как все будет сделано нажмите ENTER для продолжения"
if [ -f /tmp/mergeServers/masterServer/uniqueId.txt ] && [ -f /tmp/mergeServers/masterServer/queues6XXX.txt ] && [ -f /tmp/mergeServers/masterServer/miscdests.txt ];then
  echo "files exist"
  x=1
fi
done
### ПРАВКА ASTERISK
#functions table_name uniqueId Name_in_other_tables
#$1=какую таблицу обновляем $2=какой id обновляем
updateMysql "announcement" "announcement_id"
updateMysql "incoming" "id"
updateMysql "ivr_details" "id"
updateMysql "miscdests" "id"
updateMysql "outbound_routes" "route_id"
updateMysql "recordings" "id"
updateMysql "timeconditions" "timeconditions_id"
updateMysql "timegroups_groups" "id"
updateMysql "timegroups_details" "id"
updateMysql "trunks" "trunkid"
updateMysqlQueuesAndRingGroups
#$1=с каким параметром работаем в смежных таблицах $2=как этот параметр выглядит в этих таблицах
updateMysqlOtherTables "announcement" "app-announcement-"
updateMysqlOtherTables "ivr_details" "ivr-"
updateMysqlOtherTables "miscdests" "ext-miscdests"
updateMysqlOtherTables "timeconditions" "timeconditions"
updateMysqlOtherTables "queues" "ext-queues"
updateMysqlOtherTables "pre-queues" "pre-queue-dial"
updateMysqlOtherTables "ringgroups" "ext-group"
findAnomalyInOtherTables
#ext-meetme,75474,1
#$1=какую таблицу обновляем $2=какой id обновляем в суб таблице $3=из какой таблицы берем id
updateMysqlSubtable "ivr_entries" "ivr_id" "ivr_details"
updateMysqlSubtable "outbound_route_patterns" "route_id" "outbound_routes"
updateMysqlSubtable "outbound_route_sequence" "route_id" "outbound_routes"
updateMysqlSubtable "outbound_route_trunks" "route_id" "outbound_routes"
updateMysqlSubtable "outbound_route_trunks" "trunk_id" "trunks"
updateMysqlSubtable "pjsip" "id" "trunks"
updateMysqlSubtable "timegroups_details" "timegroupid" "timegroups_groups"
updateMysqlSubtable "trunk_dialpatterns" "trunkid" "trunks"
#$1=какую таблицу обновляем $2=id столбца с записями
updateMysqlRecordingsSubtable "announcement" "recording_id"
updateMysqlRecordingsSubtable "findmefollow" "annmsg_id"
updateMysqlRecordingsSubtable "ivr_details" "announcement"
updateMysqlRecordingsSubtable "meetme" "joinmsg_id"
updateMysqlRecordingsSubtable "queues_config" "agentannounce_id"
updateMysqlRecordingsSubtable "queues_config" "callconfirm_id"
updateMysqlRecordingsSubtable "queues_config" "joinannounce_id"
updateMysqlRecordingsSubtable "ringgroups" "annmsg_id"
updateMysqlRecordingsSubtable "ringgroups" "remotealert_id"
updateMysqlRecordingsSubtable "ringgroups" "toolate_id"
cpUsedRecordings
#makeCusromDestinations

### ПРАВКА CC_KONTUR
updateMysqlKontur "actions_log" "id"
updateMysqlKontur "agents" "id"
updateMysqlKontur "cdr_agents" "id"
updateMysqlKontur "cdr" "id"
updateMysqlKontur "cdr_cdr" "id"
updateMysqlKontur "cdr_dialer" "id"
updateMysqlKontur "cdr_dialout" "id"
updateMysqlKontur "cdr_direct" "id"
updateMysqlKontur "cdr_events" "id"
updateMysqlKontur "cdr_external" "id"
updateMysqlKontur "cdr_ivr" "id"
updateMysqlKontur "cdr_queues" "id"
updateMysqlQueuesKontur
updateMysqlSubtableKontur "actions_log" "agent_id" "kontur_agents"
updateMysqlSubtableKontur "cdr_agents" "agent_id" "kontur_agents"
updateMysqlSubtableKontur "cdr_dialout" "agent_id" "kontur_agents"
updateMysqlSubtableKontur "cdr_direct" "agent_id" "kontur_agents"