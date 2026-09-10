# Static Tcl source resolution only. This is NOT Quartus compilation.
proc set_instance_assignment {args} {}
proc set_location_assignment {args} {}
proc unknown {name args} {
    # Quartus supports unquoted bus suffixes in its inherited pin scripts.
    if {[regexp {^[0-9*]+$} $name] && [llength $args]==0} {return "\[$name\]"}
    error "unsupported Tcl command: $name $args"
}
proc set_global_assignment {args} {
    set i [lsearch -exact $args -name]
    if {$i < 0} {error "missing assignment name"}
    set name [lindex $args [expr {$i+1}]]
    set value [lindex $args [expr {$i+2}]]
    if {$name eq "VERILOG_MACRO"} {puts "MACRO\t$value"}
    if {$name in {QIP_FILE SYSTEMVERILOG_FILE VERILOG_FILE VHDL_FILE SDC_FILE}} {
        set path [file normalize $value]
        if {![file exists $path]} {error "missing $name: $path"}
        puts "$name\t$path"
        if {$name eq "QIP_FILE"} {
            set old $::quartus(qip_path)
            set ::quartus(qip_path) [file dirname $path]
            source $path
            set ::quartus(qip_path) $old
        }
    }
}
set qsf [file normalize [lindex $argv 0]]
cd [file dirname $qsf]
set ::quartus(qip_path) [pwd]
source $qsf
