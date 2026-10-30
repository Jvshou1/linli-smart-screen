# Rebuild from RTL with an explicit placement seed. GUI cached settings cannot
# change this seed. Each invocation keeps its reports in a separate directory.
set project_dir [file dirname [file normalize [info script]]]
set workspace_dir [file normalize "$project_dir/../.."]
set source_dir [file normalize "$project_dir/../user_source"]
set project_name "HDMI1.4b_Transmitter_v1.0"
set place_seed 11
if {[info exists ::env(SIXBANK_PLACE_SEED)]} {
    set place_seed $::env(SIXBANK_PLACE_SEED)
}
# TD 6.2.1 has crashed in phy_1/Hold Fix with the default seed and seed 2.
# Seed 11 also matches the saved phy_1 settings in the existing GUI project.
if {$place_seed == 2} {
    puts "WARNING: placement seed 2 is disabled after TD phy_1 access violation; using seed 11"
    set place_seed 11
}
set output_dir "$workspace_dir/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/codex_build_seed$place_seed"
set run_dir "$output_dir/[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]"
file mkdir $run_dir

set rc [catch {
    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project "$project_dir/$project_name.al" -single_run
    load_run_param -run syn_1
    elaborate -top top
    cd $run_dir
    read_adc "$source_dir/constraints_source/pin.adc"
    read_sdc "$source_dir/constraints_source/timing.sdc"
    read_sdc -ip rfifo_32_32_512 "$source_dir/hdl_source/ip/afifo_32_16_256.tcl"
    read_sdc -ip wfifo_32_32_512 "$source_dir/hdl_source/ip/afifo_16_32_256.tcl"
    optimize_rtl
    optimize_gate -packarea sixbank_gate.area
    legalize_phy_inst
    set_param place seed $place_seed
    set_param route fix_hold on
    place
    route
    report_timing_summary -file sixbank_timing.rpt
    bitgen -bit "${project_name}_sixbank_sd_fix.bit"
    # Publish only after successful bitgen; the timestamped run is retained.
    file copy -force "${project_name}_sixbank_sd_fix.bit" "$output_dir/${project_name}_sixbank_sd_fix.bit"
    set current_bit "$project_dir/${project_name}_Runs/${project_name}_sixbank_sd_fix_current.bit"
    file copy -force "${project_name}_sixbank_sd_fix.bit" $current_bit
    puts "SIXBANK_BUILD_COMPLETE: $current_bit"
    puts "TIMING_REPORT: $run_dir/sixbank_timing.rpt"
} result]
if {$rc} {
    puts stderr "SIXBANK_BUILD_FAILED: $result"
    puts stderr "RUN_DIRECTORY: $run_dir"
    exit 1
}
exit 0
