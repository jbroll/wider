if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded xgetimage 0.2 [list ::apply {dir {
    source [file join $dir critcl-rt.tcl]
    set path [file join $dir [::critcl::runtime::MapPlatform]]
    set ext [info sharedlibextension]
    set lib [file join $path "xgetimage$ext"]
    load $lib Xgetimage
    package provide xgetimage 0.2
}} $dir]
