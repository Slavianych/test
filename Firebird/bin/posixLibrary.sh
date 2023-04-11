#!/bin/sh
#
#  The contents of this file are subject to the Initial
#  Developer's Public License Version 1.0 (the "License");
#  you may not use this file except in compliance with the
#  License. You may obtain a copy of the License at
#  http://www.ibphoenix.com/main.nfs?a=ibphoenix&page=ibp_idpl.
#
#  Software distributed under the License is distributed AS IS,
#  WITHOUT WARRANTY OF ANY KIND, either express or implied.
#  See the License for the specific language governing rights
#  and limitations under the License.
#
#  The Original Code was created by Mark O'Donohue
#  for the Firebird Open Source RDBMS project.
#
#  Copyright (c) Mark O'Donohue <mark.odonohue@ludwig.edu.au>
#  and all contributors signed below.
#
#  All Rights Reserved.
#  Contributor(s): ______________________________________.
#		Alex Peshkoff
#

fb_install_prefix=/opt/firebird
default_prefix=/opt/firebird
fb_startup_name=firebird

#------------------------------------------------------------------------
# Build startup name from install path

startupName() {
	# sanity check
	if [ -z "${fb_install_prefix}" ]
	then
		echo "Empty install path - can not proceed"
		exit 1
	fi

	if [ "${fb_install_prefix}" = "${default_prefix}" ]
	then
		fb_startup_name=firebird
	else
		# strip first '/' if present
		fb_startup_name=`echo ${fb_install_prefix} | colrm 2`
		if [ ${fb_startup_name} = / ]
		then
			fb_startup_name=`echo ${fb_install_prefix} | colrm 1 1`
			if [ -z "$fb_startup_name" ]
			then
				# root specified - hmmm...
				fb_startup_name=root
			fi
		else
			echo "Parameter (${fb_install_prefix}) for -path option should start with /"
			exit 1
		fi

		# build final name
		fb_startup_name=firebird.`echo $fb_startup_name | tr / _`
	fi
}

startupName		## build it for what's present in current file


#------------------------------------------------------------------------
# Adds parameter to $PATH if it's missing in it

Add2Path() {
	Dir=${1}
	x=`echo :${PATH}: | grep :$Dir:`
	if [ -z "$x" ]
	then
		PATH=$PATH:$Dir
		export PATH
	fi
}

#------------------------------------------------------------------------
# Global stuff init

Answer=""
OrigPasswd=""
TmpFile=""
MANIFEST_TXT=""
Manifest=manifest.txt
SecurityDatabase=security3.fdb
DefaultLibrary=libfbclient
UninstallScript=FirebirdUninstall.sh
XINETD=/etc/xinetd.d/
ArchiveDateTag=`date +"%Y%m%d_%H%M"`
export ArchiveDateTag
ArchiveMainFile="${fb_install_prefix}_${ArchiveDateTag}"
export ArchiveMainFile
#this solves a problem with sudo env missing sbin
Add2Path /usr/sbin
Add2Path /sbin

#------------------------------------------------------------------------
# Create temporary file. In case mktemp failed, do something...

MakeTemp() {
	TmpFile=`mktemp $mktOptions /tmp/firebird_install.XXXXXX`
	if [ $? -ne 0 ]
	then
		for n in `seq 1000`
		do
			TmpFile=/tmp/firebird_install.$n
			if [ ! -e $TmpFile ]
			then
				touch $TmpFile
				return
			fi
		done
	fi
}

#------------------------------------------------------------------------
# Prompt for response, store result in Answer

AskQuestion() {
    Test=$1
    DefaultAns=$2
    printf %s "$Test"
    Answer="$DefaultAns"
    read Answer

    if [ -z "$Answer" ]
    then
        Answer="$DefaultAns"
    fi
}


#------------------------------------------------------------------------
# Prompt for yes or no answer - returns non-zero for no

AskYNQuestion() {
    while true
    do
    	printf %s "${*} (y/n): "
        read answer rest
        case $answer in
        [yY]*)
            return 0
            ;;
        [nN]*)
            return 1
            ;;
        *)
            echo "Please answer y or n"
            ;;
        esac
    done
}


#------------------------------------------------------------------------
# Run $1. If exit status is not zero, show output to user.

runSilent() {
	MakeTemp
	rm -f $TmpFile
	$1 >>$TmpFile 2>>$TmpFile
	if [ $? -ne 0 ]
	then
		cat $TmpFile
		echo ""
		rm -f $TmpFile
		return 1
	fi
	rm -f $TmpFile
	return 0
}


#------------------------------------------------------------------------
# Check for a user, running install, to be root

checkRootUser() {

    if [ "`whoami`" != "root" ];
      then
        echo ""
        echo "--- Stop ----------------------------------------------"
        echo ""
        echo "    You need to be 'root' user to do this change"
        echo ""
        exit 1
    fi
}

#alias
checkInstallUser() {
	checkRootUser
}


#------------------------------------------------------------------------
# Report missing library error and exit

missingLibrary() {
	libName=${1}
	echo "Please install required library '$libName' before firebird, after it repeat firebird install"
	exit 1
}


#------------------------------------------------------------------------
# Check library presence, errorexit when missing

checkLibrary() {
	libName=${1}
	haveLibrary $libName || missingLibrary $libName
}


#------------------------------------------------------------------------
# Make sure we have required libraries installed
checkLibraries() {
	if [ "N" != "Y" ]
	then
		checkLibrary tommath
	fi

	checkLibrary icudata
}


#------------------------------------------------------------------------
#  resetInetdServer
#  Works for both inetd and xinetd

resetInetdServer() {
	pid=`grepProcess "inetd|xinetd" | awk '{print $2}'`
    if [ "$pid" ]
    then
        kill -HUP $pid
    fi
}


#------------------------------------------------------------------------
# remove the xinetd config file(s)

removeXinetdEntry() {
	file="${XINETD}${fb_startup_name}"
	[ -f $file ] && rm -f $file
}


#------------------------------------------------------------------------
# remove the line from inetd file

removeInetdEntry() {
    FileName=/etc/inetd.conf
    oldLine=`grep "^gds_db" $FileName`
    removeLineFromFile "$FileName" "$oldLine"
}


#------------------------------------------------------------------------
#  Remove (x)inetd service entry and restart the service.
#  Check to see if we have xinetd installed or plain inetd.  
#  Install differs for each of them.

removeInetdServiceEntry() {
	if [ "$OS_Has_Specific_Classic_Startup" ]
	then
		osStopClassicServer
		osUnregisterClassicServer
		return
	fi

    if [ -d /etc/xinetd.d ]
    then
        removeXinetdEntry
    elif [ -f /etc/inetd.conf ]
	then
        removeInetdEntry
    fi

    # make [x]inetd reload configuration
	resetInetdServer
}


#------------------------------------------------------------------------
#  grep process by name

grepProcess() {
	processList=$1
	eol=\$
	ps $psOptions | egrep "\<($processList)($eol|[[:space:]])" | grep -v grep | grep -v -w '\-path'
}


#------------------------------------------------------------------------
#  check if it is running

checkIfServerRunning() {

	if [ "$1" != "install-embedded" ]
    then
    	stopSuperServerIfRunning
    fi


# Check is server is being actively used.

    checkString=`grepProcess "firebird"`
    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi

    checkString=`grepProcess "fb_smp_server"`
    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird SuperClassic server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi

    checkString=`grepProcess "fbserver|fbguard"`
    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird Super server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi

    checkString=`grepProcess "fb_inet_server|gds_pipe"`
    if [ ! -z "$checkString" ]
    then
        echo "An instance of the Firebird Classic server seems to be running."
        echo "Please quit all Firebird applications and then proceed."
        exit 1
    fi


# The following check for running interbase or firebird 1.0 servers.

    checkString=`grepProcess "ibserver|ibguard"`
    if [ ! -z "$checkString" ] 
    then
        echo "An instance of the Firebird/InterBase Super server seems to be running." 
        echo "(the ibserver or ibguard process was detected running on your system)"
        echo "Please quit all Firebird applications and then proceed."
        exit 1 
    fi

    checkString=`grepProcess "gds_inet_server|gds_pipe"`
    if [ ! -z "$checkString" ] 
    then
        echo "An instance of the Firebird/InterBase Classic server seems to be running." 
        echo "(the gds_inet_server or gds_pipe process was detected running on your system)"
        echo "Please quit all Firebird applications and then proceed." 
        exit 1 
    fi

# have to be root to modify (x)inetd
	if [ "$1" != "install-embedded" ]
	then
		removeInetdServiceEntry
	fi
}


#------------------------------------------------------------------------
#  ask user to enter CORRECT original DBA password

askForOrigDBAPassword() {
    OrigPasswd=""
    while [ -z "$OrigPasswd" ]
    do
        AskQuestion "Please enter current password for SYSDBA user: "
        OrigPasswd=$Answer
        if ! runSilent "${fb_install_prefix}/bin/gsec -user sysdba -password $OrigPasswd -di"
		then
			OrigPasswd=""
		fi
	done
}


#------------------------------------------------------------------------
#  Ask user to enter new DBA password string
#  !! This routine is interactive !!

getNewDBAPasswordFromUser()
{
	AskQuestion "Please enter new password for SYSDBA user: "
	NewPasswd=$Answer
}


#------------------------------------------------------------------------
# add a line in the (usually) /etc/services or /etc/inetd.conf file
# Here there are three cases, not found         => add
#                             found & different => replace
#                             found & same      => do nothing
#

replaceLineInFile() {
    FileName="$1"
    newLine="$2"
    oldLine=`grep "$3" $FileName`

    if [ -z "$oldLine" ] 
      then
        echo "$newLine" >> "$FileName"
    elif [ "$oldLine" != "$newLine"  ]
      then
		MakeTemp
        grep -v "$oldLine" "$FileName" > "$TmpFile"
        echo "$newLine" >> $TmpFile
        cp $TmpFile $FileName && rm -f $TmpFile
        echo "Updated $1"
    fi
}


#------------------------------------------------------------------------
# "edit" file $1 - replace line starting from $2 with $3

editFile() {
    FileName=$1
    Starting=$2
    NewLine=$3

	AwkProgram="(/^$Starting.*/ || \$1 == \"$Starting\") {\$0=\"$NewLine\"} {print \$0}"
	MakeTemp
	awk "$AwkProgram" <$FileName >$TmpFile && mv $TmpFile $FileName || rm -f $TmpFile
}


#------------------------------------------------------------------------
# remove line from config file if it exists in it.

removeLineFromFile() {
    FileName=$1
    oldLine=$2

    if [ ! -z "$oldLine" ]
    then
        cat $FileName | grep -v "$oldLine" > ${FileName}.tmp
        cp ${FileName}.tmp $FileName && rm -f ${FileName}.tmp
    fi
}


#------------------------------------------------------------------------
# Write new password to the ${fb_install_prefix}/SYSDBA.password file

writeNewPassword() {
    NewPasswd=$1
	DBAPasswordFile=${fb_install_prefix}/SYSDBA.password
	FB_HOST=`hostname`
	FB_TIME=`date`

	cat <<EOT >$DBAPasswordFile
#
# Firebird generated password for user SYSDBA is:
#
ISC_USER=sysdba
ISC_PASSWORD=$NewPasswd
#
# Also set legacy variable though it can't be exported directly
#
ISC_PASSWD=$NewPasswd
#
# generated on $FB_HOST at time $FB_TIME
#
# Your password can be changed to a more suitable one using
# SQL operator ALTER USER.
#
EOT

    chmod u=r,go= $DBAPasswordFile
}


#------------------------------------------------------------------------
#  Set sysdba password.

setDBAPassword() {
	writePassword=

	if [ -z "$InteractiveInstall" ]
	then
		passwd=`createNewPassword`
		writePassword=yes
	else
		NewPasswd=""
		getNewDBAPasswordFromUser
		passwd=$NewPasswd

		if [ -z "$passwd" ]
		then
			echo " "
			echo "Press enter once more if you need random password"
			echo "or enter non-empty password."
			echo " "
			getNewDBAPasswordFromUser
			passwd=$NewPasswd

			if [ -z "$passwd" ]
			then
				passwd=`createNewPassword`
				writePassword=yes
			fi
		fi
	fi

	if [ -z "$passwd" ]
	then
		passwd=masterkey
	fi

    runSilent "${fb_install_prefix}/bin/gsec -add sysdba -pw $passwd"

	if [ "$writePassword" ]
	then
		writeNewPassword $passwd
	fi
}


#------------------------------------------------------------------------
#  buildUninstallFile
#  This will work only for the .tar.gz install and it builds an
#  uninstall shell script.

buildUninstallFile() {
    cd "$origDir"

    if [ ! -f $Manifest ]  # Only exists if we are a .tar.gz install
    then
        return
    fi

	MANIFEST_TXT=${fb_install_prefix}/misc/$Manifest
	if [ "${fb_install_prefix}" = "${default_prefix}" ]
	then
		cp $Manifest $MANIFEST_TXT
	else
		newManifest $Manifest $MANIFEST_TXT
	fi

	[ -f ${fb_install_prefix}/bin/$UninstallScript ] && chmod u=rx,go= ${fb_install_prefix}/bin/$UninstallScript
}


#------------------------------------------------------------------------
#  newManifest
#  Create new manifest replacing default_prefix with fb_install_prefix
#	in existing manifest

newManifest() {
	ExistingManifestFile=${1}
	CreateManifestFile=${2}

	rm -f $CreateManifestFile
	oldPath=".${default_prefix}"

	for line in `grep "^${oldPath}" $ExistingManifestFile | colrm 1 ${#oldPath}`
	do
		echo ".${fb_install_prefix}${line}" >>$CreateManifestFile
	done

	newPath=`dirname "${fb_install_prefix}"`
	while [ ${#newPath} -gt 1 ]
	do
		echo ".${newPath}" >>$CreateManifestFile
		newPath=`dirname $newPath`
	done
}

#------------------------------------------------------------------------
# Remove if only a link

removeIfOnlyAlink() {
	Target=$1

    if [ -L $Target ]
    then
        rm -f $Target
    fi
}


#------------------------------------------------------------------------
# re-link new file only if target is a link or missing

safeLink() {
	Source=$1
	Target=$2
	Manifest=$3

	if [ $Source != $Target -a "${fb_install_prefix}" = "${default_prefix}" ]
	then
		removeIfOnlyAlink $Target
    	if [ ! -e $Target ]
	    then
    		ln -s $Source $Target
    		if [ -f "$Manifest" ]
    		then
    			echo $Target >>$Manifest
    		fi
    	fi
    fi
}


#------------------------------------------------------------------------
#  createLinksForBackCompatibility
#  Create links for back compatibility to InterBase and Firebird1.0
#  linked systems.

createLinksForBackCompatibility() {

    # These two links are required for compatibility with existing ib programs
    # If the program had been linked with libgds.so then this link is required
    # to ensure it loads the fb equivalent.  MOD 7-Nov-2002.

   	newLibrary=${fb_install_prefix}/lib/$DefaultLibrary.so
	LibDir=`CorrectLibDir /usr/lib64`
	safeLink $newLibrary $LibDir/libgds.so
	safeLink $newLibrary $LibDir/libgds.so.0
}


#------------------------------------------------------------------------
#  createLinksInSystemLib
#  Create links to firebird client library in system directory.

createLinksInSystemLib() {
	LibDir=`CorrectLibDir /usr/lib64`
	tommath=libtommath.so
	tomdir=${fb_install_prefix}/lib/.tm
    origDirLinksInSystemLib=`pwd`

    cd ${fb_install_prefix}/lib
	Libraries=`echo libfbclient.so* libib_util.so`

	cd /
	for l in $Libraries
	do
		safeLink ${fb_install_prefix}/lib/$l .$LibDir/$l ${MANIFEST_TXT}
	done

	if [ -d $tomdir ]; then
		cd $tomdir
		Libraries=""
		if [ ! -f $LibDir/$tommath ]; then
			Libraries=`echo ${tommath}*`
		fi

		cd /
		for l in $Libraries
		do
			safeLink ${fb_install_prefix}/lib/.tm/$l .$LibDir/$l ${MANIFEST_TXT}
		done
	fi

    cd $origDirLinksInSystemLib

	reconfigDynamicLoader
}

#------------------------------------------------------------------------
#  removeLinksForBackCompatibility
#  Remove links for back compatibility to InterBase and Firebird1.0
#  linked systems.

removeLinksForBackCompatibility() {
	LibDir=`CorrectLibDir /usr/lib64`

    removeIfOnlyAlink $LibDir/libgds.so
    removeIfOnlyAlink $LibDir/libgds.so.0
}


#------------------------------------------------------------------------
# Run process and check status

runAndCheckExit() {
    Cmd=$*

    $Cmd
    ExitCode=$?

    if [ $ExitCode -ne 0 ]
    then
        echo "Install aborted: The command $Cmd "
        echo "                 failed with error code $ExitCode"
        exit $ExitCode
    fi
}


#------------------------------------------------------------------------
#  Display message if this is being run interactively.

displayMessage() {
    msgText=$1

    if [ ! -z "$InteractiveInstall" ]
    then
        echo $msgText
    fi
}


#------------------------------------------------------------------------
#  Archive any existing prior installed files.
#  The 'cd' stuff is to avoid the "leading '/' removed message from tar.
#  for the same reason the DestFile is specified without the leading "/"

archivePriorInstallSystemFiles() {
	if [ -z ${ArchiveMainFile} ]
	then
		echo "Variable ArchiveMainFile not set - exiting"
		exit 1
	fi

	tarArc=${ArchiveMainFile}.$tarExt
    oldPWD=`pwd`
	distManifest=${oldPWD}/manifest.txt
    archiveFileList=""
    archiveDelTemp=""

	if [ "${fb_install_prefix}" != "${default_prefix}" ]
	then
		TmpFile=""
		MakeTemp
		newManifest $distManifest $TmpFile
		distManifest=$TmpFile
		archiveDelTemp=$TmpFile
	fi


    cd /

	if [ -f ${distManifest} ]; then
		manifest=`cat ${distManifest}`
		for i in $manifest; do
			if [ -f $i ]; then
				i=${i#/}	# strip off leading /
				archiveFileList="$archiveFileList $i"
			fi
		done
	fi

	rm -f "$archiveDelTemp"

    DestFile=${fb_install_prefix}
    if [ -e "$DestFile" ]
    then
        echo ""
        echo ""
        echo ""
        echo "--- Warning ----------------------------------------------"
        echo "    The installation target directory $DestFile already exists."
        echo "    This and other related files found will be"
        echo "    archived in the file : ${tarArc}"
        echo "" 

        if [ ! -z "$InteractiveInstall" ]
        then
            AskQuestion "Press return to continue or ^C to abort"
        fi

        if [ -e $DestFile ]
        then
            archiveFileList="$archiveFileList $DestFile"
        fi
    fi

	if [ "${fb_install_prefix}" = "${default_prefix}" ]
	then
	    for i in ibase.h ib_util.h
    	do
        	DestFile=usr/include/$i
	        if [ -e $DestFile ]; then
				if [ ! "`echo $archiveFileList | grep $DestFile`" ]; then
        	    	archiveFileList="$archiveFileList $DestFile"
				fi
	        fi
    	done

	    for i in libib_util.so libfbclient.so*
		do
			for DestFile in usr/lib/$i
			    do
        		if [ -e $DestFile ]; then
					if [ ! "`echo $archiveFileList | grep $DestFile`" ]; then
    	        		archiveFileList="$archiveFileList $DestFile"
					fi
    	    	fi
			done
	    done

	    for i in usr/sbin/rcfirebird etc/init.d/firebird etc/rc.d/init.d/firebird
    	do
        	DestFile=./$i
	        if [ -e $DestFile ]; then
				if [ ! "`echo $archiveFileList | grep $DestFile`" ]; then
        	    	archiveFileList="$archiveFileList $DestFile"
				fi
	        fi
    	done
    fi

    if [ ! -z "$archiveFileList" ]
    then
        displayMessage "Archiving..."
        runAndCheckExit "tar -cv${tarOptions}f $tarArc $archiveFileList"
        displayMessage "Done."

        displayMessage "Deleting..."
        for i in $archiveFileList
        do
            rm -rf $i
        done
        displayMessage "Done."
    fi

    cd $oldPWD
}


#------------------------------------------------------------------------
# removeInstalledFiles
#
removeInstalledFiles() {

    origDir=`pwd`
    cd /

    for manifestFile in ${fb_install_prefix}/misc/manifest*.txt
    do
	    if [ -f "$manifestFile" ]
    	then
		    for i in `cat $manifestFile`
		    do
		        if [ -f $i -o -L $i ]
		        then
        		    rm -f $i
		            #echo $i
        		fi
		    done
		fi
    done

    cd "$origDir"
}


#------------------------------------------------------------------------
# removeUninstallFiles
# Under the install directory remove all the empty directories 
# If some files remain then

removeUninstallFiles() {
    # remove the uninstall files
    rm -f ${fb_install_prefix}/misc/manifest*.txt
    rm -f ${fb_install_prefix}/bin/$UninstallScript
}


#------------------------------------------------------------------------
# removeEmptyDirs
# Under the install directory remove all the empty directories 
# This routine loops, since deleting a directory possibly makes
# the parent empty as well

removeEmptyDirs() {

    dirContentChanged='yes'
    while [ "$dirContentChanged" ]; do
        dirContentChanged=''

		for rootDir in ${fb_install_prefix}/bin ${fb_install_prefix}/bin ${fb_install_prefix}/lib ${fb_install_prefix}/include ${fb_install_prefix}/doc ${fb_install_prefix}/UDF ${fb_install_prefix}/examples ${fb_install_prefix}/examples/empbuild \
					   ${fb_install_prefix}/help ${fb_install_prefix}/intl ${fb_install_prefix}/misc ${fb_install_prefix} ${fb_install_prefix} ${fb_install_prefix} ${fb_install_prefix} ${fb_install_prefix}/plugins \
					   ${fb_install_prefix}; do

			if [ -d $rootDir ]; then
		        for i in `find $rootDir -type d -print`; do
	       	        rmdir $i >/dev/null 2>/dev/null && dirContentChanged=$i
		        done
			fi

		done
	done
}


#------------------------------------------------------------------------
#  For security reasons most files in firebird installation are
#  root-owned and world-readable(executable) only (including firebird).

#  For some files RunUser and RunGroup (firebird)
#  must have write access - lock and log for example.

MakeFileFirebirdWritable() {
    FileName=$1
    chown $RunUser:$RunGroup $FileName

	if [ "$RunUser" = "root" ]
	# In that case we must open databases, locks, etc. to the world...
	# That's a pity, but required if root RunUser choosen.
	then
    	chmod a=rw $FileName
	else
		# This is good secure setting
	    chmod ug=rw,o= $FileName
	fi
}


#------------------------------------------------------------------------
#  fixFilePermissions
#  Change the permissions to restrict access to server programs to
#  firebird group only.  This is MUCH better from a safety point of
#  view than installing as root user, even if it requires a little
#  more work.

fixFilePermissions() {
	# First of all set owneship of all files to root
	# Build list of interesting directories all over the FS
	dirs="${fb_install_prefix}/bin ${fb_install_prefix}/bin ${fb_install_prefix} ${fb_install_prefix}/lib ${fb_install_prefix}/include/firebird ${fb_install_prefix}/doc/sql.extensions ${fb_install_prefix}/UDF \
		${fb_install_prefix}/examples ${fb_install_prefix}/examples/empbuild ${fb_install_prefix}/help ${fb_install_prefix}/intl ${fb_install_prefix}/misc ${fb_install_prefix} ${fb_install_prefix} ${fb_install_prefix} \
		${fb_install_prefix} ${fb_install_prefix}/plugins"
	dirs2=`for i in $dirs; do echo $i; done|sort|uniq`

	MakeTemp
	tmp1=$TmpFile
	MakeTemp
	tmp2=$TmpFile
	MakeTemp
	tmp3=$TmpFile
	MakeTemp
	tmp4=$TmpFile

	# Extract list of our files in that directories from manifest
	manifest=${fb_install_prefix}/misc/manifest.txt
	for i in $dirs2
	do
		grep $i manifest.txt >$tmp1
		echo $i > $tmp3
		for j in $dirs2
		do
			if [ $i != $j ]
			then
				if ! grep -q $j $tmp3
				then
					grep -v $j $tmp1 >$tmp2
					rm -f $tmp1
					mv $tmp2 $tmp1
				fi
			fi
		done
		cat $tmp1 >> $tmp4
	done

	# Change ownership
	rundir=`pwd`
	cd /
	for f in `cat $tmp4`
	do
		chown root:root $f
	done
	cd $rundir

	rm -f $tmp1 $tmp2 $tmp3 $tmp4

    # Lock files
    cd ${fb_install_prefix}
    for FileName in fb_guard
    do
        touch $FileName
        MakeFileFirebirdWritable $FileName
    done

	# Log file
	cd ${fb_install_prefix}
    touch firebird.log
    MakeFileFirebirdWritable firebird.log

    # Security database
	cd ${fb_install_prefix}
    MakeFileFirebirdWritable $SecurityDatabase

    # make examples DB(s) writable
    for i in `find ${fb_install_prefix}/examples/empbuild -name '*.fdb' -print`
    do
		MakeFileFirebirdWritable $i
    done

    # Fix QLI help
	cd ${fb_install_prefix}/help
    chmod a=r help.fdb
}


#------------------------------------------------------------------------
#  Update inetd service entry
#  This just adds/replaces the service entry line

updateInetdEntry() {
    newLine="gds_db  stream  tcp     nowait.30000      $RunUser ${fb_install_prefix}/bin/firebird firebird # Firebird Database Remote Server"
    replaceLineInFile /etc/inetd.conf "$newLine" "^gds_db"
}


#------------------------------------------------------------------------
#  Update xinetd service entry

updateXinetdEntry() {
    InitFile="${XINETD}${fb_startup_name}"
    cp ${fb_install_prefix}/misc/firebird.xinetd $InitFile

    if [ -f $InitFile ]
    then
        editFile $InitFile user "\tuser\t\t\t= $RunUser"
        editFile $InitFile server "\tserver\t\t= ${fb_install_prefix}/bin/firebird"
        yesno=yes
        [ ${fb_install_prefix} = ${default_prefix} ] && yesno=no
       	editFile $InitFile disable "\tdisable\t\t= ${yesno}"
    fi
}


#------------------------------------------------------------------------
#  Update inetd service entry
#  Check to see if we have xinetd installed or plain inetd.
#  Install differs for each of them.

updateInetdServiceEntry() {
	if ! standaloneServerInstalled
	then
		if [ "$OS_Has_Specific_Classic_Startup" ]
		then
			osRegisterClassicServer
			return
		fi

	    if [ -d /etc/xinetd.d ]
    	then
        	updateXinetdEntry
    	else
    		if [ ${fb_install_prefix} = ${default_prefix} ]
    		then
        		updateInetdEntry
        	else
        		echo "Install of classic server in non-default path is not supported with inetd - xinetd needed"
        		exit 1
        	fi
		fi
    fi
}


fbUsage() {
	pf=""
	if [ "yes" = "yes" ]
	then
		pf=', -path <install path>'
	fi

	echo "$1 option: $2. Known option(s): -silent${pf}."
	exit 1
}


#------------------------------------------------------------------------
#  parseArgs
#  Parse passed arguments.
#  Set appropriate global flags.

parseArgs() {
	flSilent=0

	while [ -n "$1" ]; do
		case "$1" in
			-silent)
				flSilent=1
				;;
			-path)
				if [ "yes" = "yes" ]
				then
					{ fb_install_prefix="$2"; }
					if [ -z "${fb_install_prefix}" ]
					then
						fbUsage "Missing argument for" "$1"
					fi
					shift
					startupName
				else
					fbUsage "Not supported" "$1"
				fi
				;;
			*)
				fbUsage Invalid "$1"
				;;
		esac
		shift
	done

	if [ $flSilent -eq 0 ]; then
		InteractiveInstall=1
		export InteractiveInstall
	fi
}


#---------------------------------------------------------------------------
#  set new prefix for fb installation

setNewPrefix() {
	binlist="${fb_install_prefix}/bin/changeServerMode.sh ${fb_install_prefix}/bin/fb_config ${fb_install_prefix}/bin/registerDatabase.sh ${fb_install_prefix}/bin/FirebirdUninstall.sh"
	filelist="$binlist ${fb_install_prefix}/misc/firebird.init.d.*"
	for file in $filelist
	do
		editFile $file fb_install_prefix "fb_install_prefix=${fb_install_prefix}"
	done
	for file in $binlist
	do
		chmod 0700 $file
	done
}


#---------------------------------------------------------------------------
#  extract installation archive

extractBuildroot() {
	displayMessage "Extracting install data"

	if [ "${fb_install_prefix}" = "${default_prefix}" ]
	then
		# Extract archive in root directory
		cd /
		tar -xzof "$origDir/buildroot.tar.gz"
	else
		mkdir -p ${fb_install_prefix}
		cd ${fb_install_prefix}
		defDir=".${default_prefix}"
		if [ -d $defDir ]
		then
			echo "${default_prefix} should not exist in ${fb_install_prefix}"
		fi

		tar -xzof "$origDir/buildroot.tar.gz" ${defDir}
		for p in ${defDir}/*
		do
			mv $p .
		done

		while [ ${#defDir} -gt 2 ]
		do
			rm -rf ${defDir}
			defDir=`dirname $defDir`
		done
	fi

	cd "$origDir"
}


#---------------------------------------------------------------------------
#  depending upon presence of startup script starts super or classic server

startFirebird() {
	if [ "${fb_install_prefix}" = "${default_prefix}" ]
	then
		if standaloneServerInstalled; then
			startService
		else
			if [ "$OS_Has_Specific_Classic_Startup" ]
			then
				osStartClassicServer
				return
			fi

			resetInetdServer
		fi
	fi
}
