require 'one_gadget/gadget'
# https://gitlab.com/david942j/libcdb/blob/master/libc/libc6_2.27-3ubuntu1.2_amd64/lib/x86_64-linux-gnu/libc-2.27.so
# 
# Advanced Micro Devices X86-64
# 
# GNU C Library (Ubuntu GLIBC 2.27-3ubuntu1.2) stable release version 2.27.
# Copyright (C) 2018 Free Software Foundation, Inc.
# This is free software; see the source for copying conditions.
# There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.
# Compiled by GNU CC version 7.5.0.
# libc ABIs: UNIQUE IFUNC
# For bug reporting instructions, please see:
# <https://bugs.launchpad.net/ubuntu/+source/glibc/+bugs>.

build_id = File.basename(__FILE__, '.rb').split('-').last
OneGadget::Gadget.add(build_id, 324453,
                      constraints: ["rsp & 0xf == 0", "rcx == NULL"],
                      effect: "execve(\"/bin/sh\", rsp+0x40, environ)")
OneGadget::Gadget.add(build_id, 324546,
                      constraints: ["[rsp+0x40] == NULL"],
                      effect: "execve(\"/bin/sh\", rsp+0x40, environ)")
OneGadget::Gadget.add(build_id, 939775,
                      constraints: ["[r14] == NULL || r14 == NULL", "[r12] == NULL || r12 == NULL"],
                      effect: "execve(\"/bin/sh\", r14, r12)")
OneGadget::Gadget.add(build_id, 940216,
                      constraints: ["[[rbp-0x88]] == NULL || [rbp-0x88] == NULL", "[[rbp-0x70]] == NULL || [rbp-0x70] == NULL"],
                      effect: "execve(\"/bin/sh\", [rbp-0x88], [rbp-0x70])")
OneGadget::Gadget.add(build_id, 940223,
                      constraints: ["[r10] == NULL || r10 == NULL", "[[rbp-0x70]] == NULL || [rbp-0x70] == NULL"],
                      effect: "execve(\"/bin/sh\", r10, [rbp-0x70])")
OneGadget::Gadget.add(build_id, 940227,
                      constraints: ["[r10] == NULL || r10 == NULL", "[rdx] == NULL || rdx == NULL"],
                      effect: "execve(\"/bin/sh\", r10, rdx)")
OneGadget::Gadget.add(build_id, 1090652,
                      constraints: ["[rsp+0x70] == NULL"],
                      effect: "execve(\"/bin/sh\", rsp+0x70, environ)")
OneGadget::Gadget.add(build_id, 1090664,
                      constraints: ["[rsi] == NULL || rsi == NULL", "[[rax]] == NULL || [rax] == NULL"],
                      effect: "execve(\"/bin/sh\", rsi, [rax])")

