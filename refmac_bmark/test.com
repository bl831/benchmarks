#! /bin/csh -f
#
#	refmac benchmark testing script
#
#
#
# set these to a FAST directory (local)
setenv CCP4_SCR .
setenv BINSORT_SCR .
set tempfile = tempfile$$

set itrs = 3

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


# jiffy for finding refmac executable

foreach refmac ( $* `which refmac5` ./refmac5 refmac5 )
    if(-e $refmac) break
end

if((! $?CLIBD)||(! $?CLIBD_MON)||(! $?CINCL) && -e ./data/monomers/ ) then

    # do minimal setup
    setenv CINCL    .
    setenv CLIBD    ./data/
    setenv CLIBD_MON ./data/monomers/

    setenv LD_LIBRARY_PATH ./lib/
endif



# probe machine for info
set uname = `uname -a`


foreach itr ( `seq 1 $itrs` )

echo "refining for 10 cycles with $refmac"
rm -f refmacout.mtz
./refmac.com $refmac >! refmac${itr}.log &


sleep 5
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

set test = `ls -l refmacout.mtz | awk '{print ($5>1000000)}'`
if("$test" != "1") then
    set BAD = "$refmac failed to run"
    goto exit
endif

awk '/Times: User:/{print}' refmac${itr}.log |\
 tee -a timings.txt

end

set test = `cat timings.txt | wc -l` 
if("$test" == "0") then
    set BAD = "no results."
    goto exit
endif



send:
# make this cumulative
touch results.txt
sort -u timings.txt | awk '{print "runtime: ",$0}' >> results.txt
hostname >> results.txt
grep version refmac1.log >> results.txt
awk '! seen[$0]{print;++seen[$0]}' machineinfo.txt >> results.txt


if($?NOSEND) then
    echo "please send in your results by running: $0 send"
    goto exit
endif
echo "sending results..."
set sanskrit = `gzip -c results.txt | base64 | awk '{gsub("/","_");gsub("+","-");printf("%s",$0)}'`
if("$sanskrit" != "") then
    curl http://bl831.als.lbl.gov/refmac_bench$sanskrit > /dev/null
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





exit




# on most machines:

mkdir -p ~/projects/benchmarks/refmac/
#curl http://bl831.als.lbl.gov/~jamesh/benchmarks/refmac_bmark.tgz >! ~/projects/benchmarks/refmac/refmac_bmark.tgz
mkdir -p /dev/shm/refmac_bench/
cd /dev/shm/refmac_bench
tar xzvf ~/projects/benchmarks/refmac/refmac_bmark.tgz
cd refmac_bmark/
./test.com nosend
cp results.txt ~/projects/benchmarks/refmac/results_`hostname -s`.txt

cd ../
tar xzvf ~/projects/benchmarks/refmac/refmac_bmark.tgz
cd refmac_bmark/
rm -f results.txt
./test.com nosend
cp results.txt ~/projects/benchmarks/refmac/results_`hostname -s`.txt







# figuring out what we need to pack for lunch
./refmac.com | & tee strace.log | grep -i ccp4


 grep ccp4 strace.log | awk -F '"' '/^open/{print $2}' | awk '/.so$/{print "cp",$1,"lib"}'

 grep ccp4 strace.log | awk -F '"' '/^open/{print $2}' | awk '/data/{file=substr($1,index($1,"data"));dir=file;while(gsub("[^/]$","",dir));print "mkdir -p",dir,"; cp",$1,file}'


