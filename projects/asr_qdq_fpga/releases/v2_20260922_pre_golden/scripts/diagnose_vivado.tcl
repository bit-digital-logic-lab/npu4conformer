# Read-only package diagnostics; no global installation modifications.
puts "AUTO_PATH: $auto_path"
foreach p {::tclapp::support::appinit ::tclapp::xilinx::xsim} {
    if {[catch {package require $p} detail]} {
        puts "PACKAGE $p FAILED: $detail"
        puts $::errorInfo
    } else {puts "PACKAGE $p: $detail"}
}
if {[catch {::tclapp::support::appinit::load_app [::tclapp::get_user_repo_path] ::tclapp::xilinx::xsim} detail]} {
    puts "LOAD_APP FAILED: $detail"
    puts $::errorInfo
}
