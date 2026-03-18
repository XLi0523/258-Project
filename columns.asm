################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Columns.
#
# Student 1: Xinyue Li, 1010949583
# Student 2: Name, Student Number (if applicable)
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000
# List of colors: red, green, blue, yellow, purple, orange
colors:
    .word 0x00ff0000, 0x0000ff00, 0x000000ff,0x00ffff00, 0x00911ca6, 0x00f5691d
# List of gem colors
gem_colors:
    .word 0x0, 0x0, 0x0
grid:
    .space 4096
other_grid:
    .space 4096  
start_string:
    .asciiz "Press g to start. Use a,d,w,s. Press q to quit.\n"
gameover_string:
    .asciiz "Game Over\n"    
##############################################################################
# Mutable Data
##############################################################################

##############################################################################
# Code
##############################################################################
	.text
	.globl main

    # Run the game.
main:
# Initialize the game
# Draw the grid
li $t1, 0x999999 # $t1 = grey
lw $t0, ADDR_DSPL
# top horizontal line
addi $a0, $zero, 3
addi $a1, $zero, 0
addi $a2, $zero, 8
jal draw_hor_line

# bottom horizontal line
addi $a0, $zero, 3
addi $a1, $zero, 16
addi $a2, $zero, 8
jal draw_hor_line

# left vertical line
addi $a0, $zero, 3
addi $a1, $zero, 1
addi $a2, $zero, 15
jal draw_ver_line

# right vertical line
addi $a0, $zero, 10
addi $a1, $zero, 1
addi $a2, $zero, 15
jal draw_ver_line

# Print start instructions
li $v0, 4
la $a0, start_string
syscall

wait_start:
lw $t9, ADDR_KBRD
lw $t8, 0($t9)
beq $t8, 1, start_input
j wait_start

start_input:
lw $t2, 4($t9)
beq $t2, 0x67, begin_game   # g
beq $t2, 0x71, respond_to_q # q
j wait_start

begin_game:
jal clear_grid_memory
jal draw_new_gem

game_loop:
    # 1a. Check if key has been pressed
    # 1b. Check which key has been pressed
    # 2a. Check for collisions
	# 2b. Update locations (capsules)
	# 3. Draw the screen
	# 4. Sleep

    # 5. Go back to Step 1
# check if any column is full at top => game over
jal check_any_col_full
beq $v0, $zero, game_continue

li $v0, 4
la $a0, gameover_string
syscall
li $v0, 10
syscall

game_continue:
lw $t9, ADDR_KBRD
lw $t8, 0($t9)
beq $t8, 1, keyboard_input

# draw current falling gem
jal draw_gem

# sleep briefly
li $v0, 32
li $a0, 30
syscall
j game_loop

keyboard_input:
lw $t2, 4($t9)
beq, $t2, 0x61, respond_to_a
beq, $t2, 0x64, respond_to_d
beq, $t2, 0x73, respond_to_s
beq, $t2, 0x71, respond_to_w
beq, $t2, 0x71, respond_to_q
j game_loop

respond_to_a:
jal check_left_collision
beq $v0, $zero, game_loop
jal delete_gem
addi $t7, $t7, -4
j game_loop

respond_to_d:
jal check_right_collision
beq $v0, $zero, game_loop
jal delete_gem
addi $t7, $t7, 4
j game_loop

respond_to_s:
jal check_bottom_gem_collision
beq $v0, $zero, gem_landed
addi $t7, $t7, 128
j game_loop

respond_to_w:
la $t6, gem_colors
lw $t1, 8($t6)
lw $t2, 4($t6)
sw $t2, 8($t6)
lw $t2, 0($t6)
sw $t2, 4($t6)
sw $t1, 0($t6)
j game_loop

respond_to_q:
li $v0, 10
syscall

gem_landed:
jal store_gems_in_grid

match_loop:
jal check_matches
jal clear_matches
beq $v0, $zero, no_more_matches
jal drop_gems
j match_loop

no_more_matches:
jal draw_new_gem
j game_loop

# Functions
clear_grid_memory:
la $t0, grid
li $t1, 0
li $t2 4096

clear_grid_loop:
bge $t1, $t2, clear_other_start
sw $zero, 0($t0)
addi $t0, $t0, 4
addi $t1, $t1, 4
j clear_grid_loop

clear_other_start:
la $t0, other_grid
li $t1, 0

clear_other_loop:
bge $t1, $t2, clear_grid_done
sw $zero, 0($t0)
addi $t0, $t0, 4
addi $t1, $t1, 4
j clear_other_loop

clear_grid_done:
jr $ra

# Randomly generate a color for 1 gem
gem_color:
li $v0, 42
li $a0, 0
li $a1, 6
syscall
la $t4, colors
sll $t5, $a0, 2
addu $t4, $t4, $t5
lw, $t1, 0($t4)
jr $ra

# Spawn a new vertical 3-gem column at top-middle
draw_new_gem:
addi $sp, $sp, -4
sw $ra, 0($sp)
la $t6, gem_colors
jal gem_color
sw $t1, 0($t6)
jal gem_color
sw $t1, 4($t6)
jal gem_color
sw $t1, 8($t6)
lw $t0, ADDR_DSPL
addi $t7, $t0, 152
lw $ra, 0($sp)
addi $sp, $sp, 4
jr $ra

draw_gem:
la $t6, gem_colors
lw $t1, 0($t6)
sw $t1, 0($t7)
lw $t1, 4($t6)
sw $t1, 128($t7)
lw $t1, 8($t6)
sw $t1, 256($t7)
jr $ra

# Erase current vertical falling column
delete_gem:
li $t1, 0x000000
sw $t1, 0($t7)
sw $t1, 128($t7)
sw $t1, 256($t7)
jr $ra

# Store landed vertical column into grid memory
store_gems_in_grid:
addi $sp, $sp, -8
sw $ra, 0($sp)
sw $t0, 4($sp)

la $t6, gem_colors
lw $t0, ADDR_DSPL
sub $t2, $t7, $t0
la $t3, grid
add $t3, $t3, $t2

lw $t1, 0($t6)
sw $t1, 0($t3)

lw $t1, 4($t6)
sw $t1, 128($t3)

lw $t1, 8($t6)
sw $t1, 256($t3)

lw $ra, 0($sp)
lw $t0, 4($sp)
addi $sp, $sp, 8
jr $ra

# Game over
check_col_full:
# input a0 = playable column number 4..9
lw $t0, ADDR_DSPL
sll $t1, $a0, 2
add $t0, $t0, $t1
addi $t0, $t0, 128   # row 1

move $a0, $t0
jal get_color_grid
beq $v0, $zero, col_not_full

li $v0, 1
jr $ra

col_not_full:
li $v0, 0
jr $ra

check_any_col_full:
li $t0, 4

check_any_col_loop:
bgt $t0, 9, no_col_full
move $a0, $t0
jal check_col_full
bne $v0, $zero, some_col_full
addi $t0, $t0, 1
j check_any_col_loop

some_col_full:
li $v0, 1
jr $ra

no_col_full:
li $v0, 0
jr $ra
    
draw_hor_line:
lw $t0, ADDR_DSPL
sll $a0, $a0, 2
add $t2, $t0, $a0
sll $a1, $a1, 7
add $t2, $t2, $a1

sll $a2, $a2, 2
add $t3, $t2, $a2

loop_row_start:
beq $t2, $t3, loop_row_end
sw $t1, 0($t2)
addi $t2, $t2, 4
j loop_row_start

loop_row_end:
jr $ra

draw_ver_line:
lw $t0, ADDR_DSPL
sll $a0, $a0, 2
add $t2, $t0, $a0
sll $a1, $a1, 7
add $t2, $t2, $a1

sll $a2, $a2, 7
add $t3, $t2, $a2

loop_col_start:
beq $t2, $t3, loop_col_end
sw $t1, 0($t2)
addi $t2, $t2, 128
j loop_col_start

loop_col_end:
jr $ra