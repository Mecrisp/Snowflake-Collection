
.option norelax
.option rvc

.section mecrisp, "awx" # Everything is writeable and executable

.global _start
_start:

# -----------------------------------------------------------------------------
#  Prepare 1920x1080x32bpp framebuffer
# -----------------------------------------------------------------------------

framebuffer_open:
   li x10, -100                # Directory: AT_FDCWD
   la x11, device              # Device to open
   li x12, 2                   # O_RDWR
   li x17, 56                  # "openat"
   ecall                       # open("/dev/fb0", O_RDWR)
framebuffer_mmap:
   mv x14, x10                 # --> File descriptor
   la x10, 0                   # Device to open
   li x11, 1920 * 1080 * 4     # Length
   li x12, 3                   # PROT_READ | PROT_WRITE
   li x13, 1                   # MAP_SHARED
   #  x14                      # File descriptor
   li x15, 0                   # Offset
   li x17, 222                 # "mmap"
   ecall                       # mmap2(NULL, Length, PROT_READ|PROT_WRITE, MAP_SHARED, FD, 0)

   # Mapped address of framebuffer is now in x10.

   # See https://jborza.com/post/2021-05-11-riscv-linux-sysc.jals/
   # for sysc.jal numbers

   mv x3, x10

   li x31, 0
   li x15, 0x00010001

   j nextflake # Skip DAC initialisations

.align 8, 0

# -----------------------------------------------------------------------------
#
#    Snowflake Collection - Frozen surprises for Lovebyte 2023
#    Copyright (C) 2023  Matthias Koch
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

.option norelax
.option rvc

# -----------------------------------------------------------------------------
#  Peripheral IO registers
# -----------------------------------------------------------------------------

  .equ GPIOA_BASE,   0x40010800
  .equ GPIOA_CTL0,        0x000

  .equ RCU_BASE,     0x40021000
  .equ RCU_CTL,           0x000
  .equ RCU_CFG0,          0x004
  .equ RCU_APB2EN,        0x018
  .equ RCU_APB1EN,        0x01C

  .equ DAC_BASE,     0x40007000
  .equ DAC_CTL,           0x400
  .equ DACC_R12DH,        0x420

# -----------------------------------------------------------------------------
Reset:
# -----------------------------------------------------------------------------

  li x14, RCU_BASE
  li x3,  DAC_BASE

  li x15, -1
  sw x15, RCU_APB2EN(x14) # Enable PORTA and everything else
  sw x15, RCU_APB1EN(x14) # Enable DAC and everything else

  li x12, GPIOA_BASE+0x800       # Split address for shorter opcodes
  sw zero, GPIOA_CTL0-0x800(x12) # Switch DAC pins PA4 and PA5 to analog mode (PA0 to PA7, indeed)

  li x15, 0x00010001      # Enable both DAC channels by setting DEN0 and DEN1
  sw x15, DAC_CTL(x3)

# -----------------------------------------------------------------------------
#  Notes on register usage:
#
#   x3: Constant DAC_BASE
#
#   x8: Cycle length counter
#   x9: Pixel counter
#  x10: Scratch
#  x11: Scratch
#  x12: Current position, x-component
#  x13: Current position, y-component
#  x14: Unused
#  x15: Random value
#
#  x20: Home position, x-component
#  x21: Home position, y-component
#
# -----------------------------------------------------------------------------
nextflake:

  lui x9, 0x00025 # How many pixels to draw before switching to new shape

  slli x12, x15, 32-9-4  # Create new start coordinates
  srli x12, x12, 32-9

  slli x13, x15, 32-9-19
  srai x13, x13, 32-9

# -----------------------------------------------------------------------------
continue:

  c.jal clrscr

  li x8, 0 # Cycle length

  mv x20, x12 # Stop when coordinates return to the start position
  mv x21, x13

mandala:

  addi x10, x12, 1023 # Shift coordinates to the middle
  addi x11, x13, 1023 #  of the DAC range, * 2 later

  slli x10, x10, 1    # Combine both
  slli x11, x11, 17   # positions
  or x10, x10, x11    # in the format of the two DAC channels output register.
  add x15, x15, x10         # Update the "pseudo random" value
  c.jal paintpixel
# sw x10, DACC_R12DH(x3) # This way both channels get new values at the same moment

mandala_next_point_on_cycle:

  # Magic values to get closed cycles with 8-symmetry
 .equ aint, 0xCAFB0CCC + 820   #  8
 .equ bint, 0x5A82799A + 1638  # Offset to fit in LUI only

  c.jal mandala_cycle_aint
  c.add  x13, x10

  mv x10, x13
  li x11, bint
  c.jal mandala_cycle_bint
  c.add  x12, x10

  c.jal mandala_cycle_aint
  c.add  x13, x10

  addi x9, x9, -1       # Continue to display the current flake
  c.beqz x9, nextflake  # as long as there is time left

  addi x8, x8, 1 # Cycle length update

  bne x12, x20, mandala  # Check if x coordinate is back to start value
  bne x13, x21, mandala  # Check if y coordinate is back to start value

drawitagain:

  srli x8, x8, 9   # Do not accept too short cycles
  c.beqz x8, nextflake

  j continue

# -----------------------------------------------------------------------------
mandala_cycle_aint:
  mv x10, x12
  li x11, aint
mandala_cycle_bint:
  slli x10, x10, 2
  mulh   x10, x10, x11
  c.addi x10, 1
  srai   x10, x10, 1
  ret

# -----------------------------------------------------------------------------
# signature: .byte 'M', 'e', 'c', 'r', 'i', 's', 'p', '.'
# -----------------------------------------------------------------------------

# Specials for framebuffer output:

# -----------------------------------------------------------------------------
paintpixel: # Paints the value for the DACs
# -----------------------------------------------------------------------------
  mv x7, x10

  mv x5, x10
  srli x5, x5, 16

  li x4, 4095
  and x7, x7, x4
  and x5, x5, x4

  srli x7, x7, 2
  srli x5, x5, 2

  slli x7, x7, 2
  li x4, 1920*4
  mul x4, x4, x5
  add x7, x7, x4
  add x7, x7, x3

  li x4, 0x00FFFF
  sw x4, 0(x7)

  ret

# -----------------------------------------------------------------------------
clrscr:
# -----------------------------------------------------------------------------

  addi x31, x31, 1
  li x10, 8192    # Do not continue forever
  bge x31, x10, bye

  mv x10, x3
  li x11, 1920*1080*4
  add x11, x11, x3

1:sw zero, 0(x10)
  addi x10, x10, 4
  bne x10, x11, 1b
  ret

# -----------------------------------------------------------------------------
bye:
# -----------------------------------------------------------------------------
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x17, 93                  # "exit"
    ecall                       # Final system call

device:  .ascii  "/dev/fb0\000"
