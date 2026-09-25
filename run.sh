cd /home/runner
export PATH=/usr/bin:/bin:/tool/pandora64/bin:/apps/vcsmx/vcs/X-2025.06-SP1//bin:/usr/local/bin
export VCS_VERSION=X-2025.06-SP1
export VCS_PATH=/apps/vcsmx/vcs/X-2025.06-SP1//bin
export EDATOOL=vcs
export LM_LICENSE_FILE=27020@10.116.0.5
export VCS_HOME=/apps/vcsmx/vcs/X-2025.06-SP1/
export HOME=/home/runner
vcs -full64 -licqueue '-timescale=1ns/1ns' '+vcs+flush+all' '+warn=all' '-sverilog' design.sv testbench.sv  && ./simv +vcs+lic+wait  ; echo 'Creating result.zip...' && zip -r /tmp/tmp_zip_file_123play.zip . && mv /tmp/tmp_zip_file_123play.zip result.zip