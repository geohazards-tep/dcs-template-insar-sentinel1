#!/bin/bash
#
#INSAR with Sentinel 1 data development template 

# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}
# define the exit codes
SUCCESS=0
ERR_MASTER=10
ERR_SLAVE=20
ERR_EXTRACT=30
ERR_PROCESS=40
ERR_PUBLISH=50
# add a trap to exit gracefully
function cleanExit () {

  local retval=$?
  local msg=""

  case "$retval" in
    $SUCCESS) msg="Processing successfully concluded";;
    $ERR_MASTER) msg="Failed to retrieve the master product";;
    $ERR_SLAVE) msg="Failed to retrieve the slave product";;
    $ERR_EXTRACT) msg="Failed to retrieve the extract the vol and lea";;
    $ERR_PROCESS) msg="Failed during process execution";;
    $ERR_PUBLISH) msg="Failed results publish";;
    *) msg="Unknown error";;
  esac
  [ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
  exit $retval
}

trap cleanExit EXIT

#export PATH=$_CIOP_APPLICATION_PATH/myapp/bin:$PATH

param1="`ciop-getparam param1`"

function get_data() {
  masterref=$( echo "$1" | cut -d";" -f1 )
  slaveref=$( echo "$1" | cut -d";" -f2 )

  mastersafe=$( echo ${masterref} | ciop-copy -U -O ${TMPDIR}/download/master - )
  # let's check the return value
  [ $? -eq 0 ] || return ${ERR_MASTER}

  slavesafe=$( echo ${slaveref} | ciop-copy -U -O ${TMPDIR}/download/slave - )
  # let's check the return value
  [ $? -eq 0 ] || return ${ERR_SLAVE}
}

function extract_safe() {
  safe_archive=${1}
  optional=${2}
  safe=$( unzip -l ${safe_archive} | grep "SAFE" | head -n 1 | awk '{ print $4 }' | xargs -I {} basename {} )

  [ -n "${optional}" ] && safe=${optional}/${safe}
  mkdir -p ${safe}

  for annotation in $( unzip -l "${safe_archive}" | grep annotation | grep .xml | grep -v calibration | awk '{ print $4 }' )
  do
     unzip -o -j ${safe_archive} "${annotation}" -d "${safe}/annotation" 1>&2
  done

  for measurement in $( unzip -l ${safe_archive} | grep measurement | grep .tiff | awk '{ print $4 }' )
  do
    unzip -o -j ${safe_archive} "${measurement}" -d "${safe}/measurement" 1>&2
  done

  ciop-log $safe
}

function extract_data() {
  for mastersafe in $( find ${TMPDIR}/download/master -name "*.zip" )
  do
	ciop-log "INFO" "Extracting ${mastersafe}"
	# extract the SAFE content (only important annotation and measurement)
	master=$( extract_safe ${mastersafe} ${TMPDIR}/data/master )
	[ "$?" != "0" ] && return $ERR_EXTRACT
  done

  for slavesafe in $( find ${TMPDIR}/download/slave -type f -name "*.zip" )
  do
	slave=$( extract_safe ${slavesafe} ${TMPDIR}/data/slave )
	[ "$?" != "0" ] && return $ERR_EXTRACT
  done
}


function clean() {
  # free some space
  rm -rf ${TMPDIR}/download/master
  rm -rf ${TMPDIR}/download/slave
  rm -rf ${TMPDIR}/data/master
  rm -rf ${TMPDIR}/data/slave
}

function main(){

extract_data
[ "$?" != "0" ] && return $ERR_EXTRACT
  # invoke the app with the local staged data
  # stage-out the results
}

mkdir -p ${TMPDIR}/download/master
mkdir -p ${TMPDIR}/download/slave

# loop through the pairs
while read pair
do
    get_data "${pair}"
done


main || exit $?