#! /bin/csh -f
#
#	phenix.refine benchmark testing script
#
#
#
setenv PHENIX_OVERWRITE_ALL true
set itrs = 3


# probe machine for info
set uname = `uname -a`


# allow user override of parameters
foreach arg ( $* )
    if("$arg" =~ *=*) then
        set values = `echo $arg | awk -F "=" '{print $2}' | awk 'BEGIN{RS=","} {print}'`
        if("$arg" =~ itr*) then
            set itrs = `echo $arg | awk -F "=" '{print $2+0}'`
        endif
    endif
    if("$arg" == "send") then
        unset NOSEND
        goto send
    endif
    if("$arg" == "nosend") then
        set NOSEND
    endif
end


# jiffy for finding phenix executable

foreach phenix ( $* `which phenix.refine` )
    if(-e $phenix) break
end

if((! $?PHENIX_VERSION) ) then
    set BAD = "phenix must be installed"
    goto exit

    # do minimal setup
    setenv PHENIX .
    setenv PHENIX_VERSION 1.11.1
    set path = ( ./build/bin $path )

    setenv LD_LIBRARY_PATH ./lib/
endif



# figure out how to measure time

if (! -x ./log_timestamp.tcl) then
    cat << EOF >! log_timestamp.tcl
#! /bin/sh
# use tclsh in the path \
exec tclsh "\$0" "\$@"
#
#       encode a logfile stream with time stamps
#
#
#
set start [expr [clock clicks -milliseconds]/1000.0]

while { ! [eof stdin] } {
    set line "[gets stdin]"
    puts "[clock format [clock seconds] -format "%a %b %d %T %Z %Y"] [clock seconds] [format "%12.3f" [expr [clock clicks -milliseconds]/1000.0 - \$start]] \$line"

}
EOF
    chmod a+x log_timestamp.tcl
endif


set test = `echo | ./log_timestamp.tcl | awk '{print ( $7+0>1000000 )}' | tail -n 1`
if("$test" == "1") then
    set timestamper = ./log_timestamp.tcl
else
    echo "WARNING: tcl does not work, resorting to low-precision timer"
    # hmm.  Maybe tcl not installed
    cat << EOF >! timer.csh
#! /bin/csh -f
#
set starttime = \`date +%s\`

cat

set endtime = \`date +%s\`
@ deltaT = ( \$endtime - \$starttime )
echo "\`date\` \$endtime \$deltaT"
EOF
    chmod a+x timer.csh
    set timestamper = ./timer.csh
endif




touch timings.txt
foreach itr ( 1 2 3 )

echo "default refinement with phenix.refine"
phenix.refine model.pdb data.mtz  >! run${itr}.log &


sleep 10
# now that CPUs are hot, collect machine data
uname -a >! machineinfo.txt
set uname = `awk '{print $1;exit}' machineinfo.txt`
uptime >> machineinfo.txt

if("$uname" == "Linux" || "$uname" =~ CYGWIN*) then
    free -m >> machineinfo.txt
    cat /proc/cpuinfo >> machineinfo.txt
endif
if("$uname" == "Darwin") then
    sysctl hw >> machineinfo.txt
endif
set test = `cat machineinfo.txt | wc -l | awk '{print ($1<10)}'`
if($test) then
    echo "WARNING: unknown platform! "
endif
grep MHz machineinfo.txt | sort -k4gr | head -n 1

wait


set dtime = `awk '/^wall clock time:/{print $4}' run${itr}.log`
echo "runtime: $dtime" | tee -a timings.txt

end

set test = `cat timings.txt | wc -l` 
if("$test" == "0") then
    echo "ERROR: phenix.refine failed to run."
    exit 9
endif


# make this cumulative
touch results.txt
grep "^runtime: " timings.txt >> results.txt
grep -i version run1.log >> results.txt
hostname >> results.txt
cat machineinfo.txt >> results.txt



send:
echo "sending results..."

set sanskrit = `gzip -c results.txt | base64 | awk '{gsub("/","_");gsub("[+]","-");printf("%s",$0)}'`
if("$sanskrit" != "") then
    curl http://bl831.als.lbl.gov/phenixrefine_bench$sanskrit > /dev/null
endif
if($status || "$sanskrit" == "") then
    echo "ERROR: please send file results.txt manually to JMHolton@lbl.gov"
endif

exit:

if($?BAD) then
    echo "ERROR: $BAD"
    exit 9
endif

exit



# on most machines:

mkdir -p /dev/shm/phenixrefine_bench/
cd /dev/shm/phenixrefine_bench
curl http://bl831.als.lbl.gov/~jamesh/benchmarks/phenixrefine_bmark.tgz | tar xzvf -
./test.com








# figuring out what we need to pack for lunch
setenv PHENIX_OVERWRITE_ALL true
strace phenix.refine model.pdb data.mtz | & tee strace.log | grep -i open


awk -F '"' '/^open/{print $2}' strace.log | awk '/.so$/{print "cp",$1,"lib"}'

awk -F '"' '/^open/{print $2}' strace.log | awk -v key="phenix-1.11.1-2575" '$1~key{\
   print substr($0,index($0,key)+length(key)+1);}' |\
awk '! seen[$0]{print;++seen[$0]}' |\
sort -u |\
( cd $PHENIX ; tar cvTf - - ) |\
tar xvf -
mkdir -p base/bin/
cp ${PHENIX}/base/bin/python2.7 base/bin/
cp ${PHENIX}/base/lib/libpython2.7.so.1.0 base/lib/

foreach file ( ./build/bin/phenix.refine ./build/libtbx_env )
   awk '{gsub("/home/sw/rhel6/x86_64/phenix/phenix-1.11.1-2575","."); print}' $file >! new.txt
   mv new.txt $file
   chmod a+x $file
end
vi ./modules/cctbx_project/mmtbx/rotamer/rotamer_eval.py

awk ''

find . -type f  \! -name '*.pyc' -exec grep -l phenix-1.11.1- \{\} \;
find . -type f  \! -name '*.pyc' -exec grep -l utf-8 \{\} \;

\
   file=substr($1,index($1,"data"));dir=file;while(gsub("[^/]$","",dir));print "mkdir -p",dir,"; cp",$1,file}'








