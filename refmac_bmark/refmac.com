#! /bin/csh -f
#
#	REFMAC benchmark script
#
###############################################################################
set pdbin = model.pdb

set refmac = refmac5
if( $1 != "") set refmac = "$1"



###############################################################################
#
# Refmac step. Refine
#
$refmac \
HKLIN      data.mtz \
HKLOUT     ./refmacout.mtz \
XYZIN      $pdbin \
XYZOUT     ./refmacout.pdb \
<< END-OF-REFMAC 

# Actual number of REFMAC refinement steps per cycle (5 default)
NCYC 10

# verboseness
MONI FEW
#MONI MEDI HBOND
#MONI MEDI CHIRAL 0.5
#MONI MANY
# 20 display bins by default
#BINS 20
end
END-OF-REFMAC
#
# update the output file
#
# Clean up
#
exit


