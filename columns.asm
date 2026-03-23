################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Columns.
#
# Student 1: Xinyue Li, 1010949583
# Student 2: Ethan Qiu, 1010862568
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
# Stores the 3 colors of the next vertical column preview
preview_colors:
    .word 0x0, 0x0, 0x0    
grid:
    .space 4096
other_grid:
    .space 4096  
start_string:
    .asciiz "Press 1 (easy), 2 (medium), 3 (hard) to start. Use a,d,w,s. p=pause, q=quit.\n"
gameover_string:
    .asciiz "Game Over\n"
paused_string:
    .asciiz "Paused\n"
resumed_string:
    .asciiz "Resumed\n"
    .align 2
gravity_counter:
    .word 0
gravity_threshold:
    .word 17
gems_landed:
    .word 0
gems_per_speedup:
    .word 5
min_threshold:
    .word 3
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
# Draw the playing field border
    li $t1, 0x999999
    addi $a0, $zero, 3
    addi $a1, $zero, 0
    addi $a2, $zero, 8
    jal draw_hor_line
    addi $a0, $zero, 3
    addi $a1, $zero, 16
    addi $a2, $zero, 8
    jal draw_hor_line
    addi $a0, $zero, 3
    addi $a1, $zero, 1
    addi $a2, $zero, 15
    jal draw_ver_line
    addi $a0, $zero, 10
    addi $a1, $zero, 1
    addi $a2, $zero, 15
    jal draw_ver_line
    
    # Draw side preview panel border

    # top horizontal line
    addi $a0, $zero, 12
    addi $a1, $zero, 0
    addi $a2, $zero, 6
    jal draw_hor_line

    # bottom horizontal line
    addi $a0, $zero, 12
    addi $a1, $zero, 6
    addi $a2, $zero, 6
    jal draw_hor_line

    # left vertical line
    addi $a0, $zero, 12
    addi $a1, $zero, 1
    addi $a2, $zero, 5
    jal draw_ver_line

    # right vertical line
    addi $a0, $zero, 17
    addi $a1, $zero, 1
    addi $a2, $zero, 5
    jal draw_ver_line

    li $v0, 4
    la $a0, start_string
    syscall

    j wait_start

wait_start:
    lw $t9, ADDR_KBRD
    lw $t8, 0($t9)
    beq $t8, 1, start_input
    j wait_start

start_input:
    lw $t2, 4($t9)
    beq $t2, 0x31, select_easy    # 1
    beq $t2, 0x32, select_medium  # 2
    beq $t2, 0x33, select_hard    # 3
    beq $t2, 0x71, respond_to_q   # q
    j wait_start

select_easy:
    li $t0, 33
    j set_difficulty
select_medium:
    li $t0, 17
    j set_difficulty
select_hard:
    li $t0, 10
    j set_difficulty

set_difficulty:
    sw $t0, gravity_threshold

begin_game:
    sw $zero, gems_landed
    jal clear_grid_memory
    jal init_preview
    jal draw_new_gem
    jal draw_gem

    # flush the start key so old input does not linger
    lw $t9, ADDR_KBRD
    lw $t2, 4($t9)

    j game_loop
    
game_loop:
    # 1a. Check if key has been pressed
    # 1b. Check which key has been pressed
    # 2a. Check for collisions
	# 2b. Update locations (capsules)
	# 3. Draw the screen
	# 4. Sleep

    # 5. Go back to Step 1
game_continue:
    lw $t9, ADDR_KBRD
    lw $t8, 0($t9)
    beq $t8, 1, keyboard_input

gravity_tick:
    la $t0, gravity_counter
    lw $t1, 0($t0)
    addi $t1, $t1, 1
    sw $t1, 0($t0)
    lw $t2, gravity_threshold
    blt $t1, $t2, no_gravity
    sw $zero, 0($t0)

    jal check_bottom_gem_collision
    beq $v0, $zero, gem_landed
    jal delete_gem
    addi $t7, $t7, 128
    jal draw_gem
    j no_gravity

no_gravity:
    jal draw_gem

    li $v0, 32
    li $a0, 30
    syscall

    j game_loop

keyboard_input:
    lw $t2, 4($t9)
    beq $t2, 0x61, respond_to_a   # a
    beq $t2, 0x64, respond_to_d   # d
    beq $t2, 0x73, respond_to_s   # s
    beq $t2, 0x77, respond_to_w   # w
    beq $t2, 0x71, respond_to_q   # q
    beq $t2, 0x70, respond_to_p   # p
    j gravity_tick

respond_to_a:
    jal check_left_collision
    beq $v0, $zero, gravity_tick
    jal delete_gem
    addi $t7, $t7, -4
    jal draw_gem
    j gravity_tick

respond_to_d:
    jal check_right_collision
    beq $v0, $zero, gravity_tick
    jal delete_gem
    addi $t7, $t7, 4
    jal draw_gem
    j gravity_tick

respond_to_s:
    la $t0, gravity_counter
    sw $zero, 0($t0)
    jal check_bottom_gem_collision
    beq $v0, $zero, gem_landed
    jal delete_gem
    addi $t7, $t7, 128
    jal draw_gem
    j gravity_tick

respond_to_w:
    la $t6, gem_colors
    lw $t1, 8($t6)
    lw $t2, 4($t6)
    sw $t2, 8($t6)
    lw $t2, 0($t6)
    sw $t2, 4($t6)
    sw $t1, 0($t6)
    jal draw_gem
    j gravity_tick

respond_to_p:
    li $v0, 4
    la $a0, paused_string
    syscall

pause_loop:
    lw $t9, ADDR_KBRD
    lw $t8, 0($t9)
    beq $t8, $zero, pause_loop
    lw $t2, 4($t9)
    bne $t2, 0x70, pause_loop      # ignore all keys except p

    li $v0, 4
    la $a0, resumed_string
    syscall
    j gravity_tick

respond_to_q:
    li $v0, 10
    syscall

gem_landed:
    jal store_gems_in_grid

    la $t0, gems_landed
    lw $t1, 0($t0)
    addi $t1, $t1, 1
    sw $t1, 0($t0)

    lw $t2, gems_per_speedup
    div $t1, $t2
    mfhi $t3
    bne $t3, $zero, match_loop

    la $t0, gravity_threshold
    lw $t1, 0($t0)
    lw $t2, min_threshold
    ble $t1, $t2, match_loop
    addi $t1, $t1, -1
    sw $t1, 0($t0)

match_loop:
    jal check_matches
    jal clear_matches
    beq $v0, $zero, no_more_matches
    jal drop_gems
    j match_loop

no_more_matches:
    lw $t0, ADDR_DSPL
    addi $a0, $t0, 152
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    lw $t0, ADDR_DSPL
    addi $a0, $t0, 280
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    lw $t0, ADDR_DSPL
    addi $a0, $t0, 408
    jal get_color_grid
    bne $v0, $zero, spawn_blocked

    la $t0, gravity_counter
    sw $zero, 0($t0)
    jal draw_new_gem
    jal draw_gem
    j game_loop

spawn_blocked:
    li $v0, 4
    la $a0, gameover_string
    syscall
    li $v0, 10
    syscall

# Functions
clear_grid_memory:
    la $t0, grid
    li $t1, 0
    li $t2, 4096

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

gem_color:
    li $v0, 42
    li $a0, 0
    li $a1, 6
    syscall
    la $t4, colors
    sll $t5, $a0, 2
    addu $t4, $t4, $t5
    lw $t1, 0($t4)
    jr $ra

# Generate 3 random colors for the next preview column
init_preview:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t0, preview_colors

    jal gem_color
    sw $t1, 0($t0)

    jal gem_color
    sw $t1, 4($t0)

    jal gem_color
    sw $t1, 8($t0)

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra    

draw_new_gem:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t6, gem_colors
    la $t0, preview_colors

    lw $t1, 0($t0)
    sw $t1, 0($t6)

    lw $t1, 4($t0)
    sw $t1, 4($t6)

    lw $t1, 8($t0)
    sw $t1, 8($t6)

    lw $t0, ADDR_DSPL
    addi $t7, $t0, 152
    
    jal init_preview
    
    jal draw_preview_panel

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

delete_gem:
    li $t1, 0x000000
    sw $t1, 0($t7)
    sw $t1, 128($t7)
    sw $t1, 256($t7)
    jr $ra

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

get_color_grid:
    lw $t0, ADDR_DSPL
    sub $t2, $a0, $t0
    la $t3, grid
    add $t3, $t3, $t2
    lw $v0, 0($t3)
    jr $ra

check_left_collision:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, ADDR_DSPL
    sub $t1, $t7, $t0
    andi $t2, $t1, 0x7f
    srl $t2, $t2, 2

    li $t3, 4
    ble $t2, $t3, cannot_move_left

    addi $t4, $t7, -4
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left

    addi $t4, $t7, 124
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left

    addi $t4, $t7, 252
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left

    li $v0, 1
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

cannot_move_left:
    li $v0, 0
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

check_right_collision:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, ADDR_DSPL
    sub $t1, $t7, $t0
    andi $t2, $t1, 0x7f
    srl $t2, $t2, 2

    li $t3, 9
    bge $t2, $t3, cannot_move_right

    addi $t4, $t7, 4
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right

    addi $t4, $t7, 132
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right

    addi $t4, $t7, 260
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right

    li $v0, 1
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

cannot_move_right:
    li $v0, 0
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

check_bottom_gem_collision:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, ADDR_DSPL
    sub $t1, $t7, $t0
    srl $t2, $t1, 7

    li $t3, 13
    bge $t2, $t3, cannot_move_down

    addi $t4, $t7, 384
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down

    li $v0, 1
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

cannot_move_down:
    li $v0, 0
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

##############################################################################
# Matching logic
##############################################################################

# Clear other_grid, then scan vertical / horizontal / diagonal
check_matches:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t0, other_grid
    li $t1, 0
    li $t2, 4096

clear_matches_grid:
    bge $t1, $t2, check_vertical_start
    sw $zero, 0($t0)
    addi $t0, $t0, 4
    addi $t1, $t1, 4
    j clear_matches_grid

check_vertical_start:
    jal check_vertical_matches
    jal check_horizontal_match
    jal check_diagonal_matches

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# Mark a position in other_grid
mark_match:
    lw $t0, ADDR_DSPL
    sub $t1, $a0, $t0
    la $t2, other_grid
    add $t2, $t2, $t1
    li $t3, 1
    sw $t3, 0($t2)
    jr $ra

# Vertical match check
check_vertical_matches:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s0, 4              # col = 4..9

vertical_col_loop:
    bgt $s0, 9, vertical_done

    li $s1, 1              # row = 1..13

vertical_row_loop:
    bgt $s1, 13, next_vertical_col

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1      # s2 = display address of current cell

    move $a0, $s2
    jal get_color_grid
    move $s3, $v0
    beq $s3, $zero, vertical_next_row

    addi $a0, $s2, 128
    jal get_color_grid
    bne $v0, $s3, vertical_next_row

    addi $a0, $s2, 256
    jal get_color_grid
    bne $v0, $s3, vertical_next_row

    move $a0, $s2
    jal mark_match
    addi $a0, $s2, 128
    jal mark_match
    addi $a0, $s2, 256
    jal mark_match

vertical_next_row:
    addi $s1, $s1, 1
    j vertical_row_loop

next_vertical_col:
    addi $s0, $s0, 1
    j vertical_col_loop

vertical_done:
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    addi $sp, $sp, 20
    jr $ra

# Horizontal match check
check_horizontal_match:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s1, 1              # row = 1..15

horizontal_row_loop:
    bgt $s1, 15, horizontal_done

    li $s0, 4              # col = 4..7

horizontal_col_loop:
    bgt $s0, 7, next_horizontal_row

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1      # s2 = display address

    move $a0, $s2
    jal get_color_grid
    move $s3, $v0
    beq $s3, $zero, horizontal_next_col

    addi $a0, $s2, 4
    jal get_color_grid
    bne $v0, $s3, horizontal_next_col

    addi $a0, $s2, 8
    jal get_color_grid
    bne $v0, $s3, horizontal_next_col

    move $a0, $s2
    jal mark_match
    addi $a0, $s2, 4
    jal mark_match
    addi $a0, $s2, 8
    jal mark_match

horizontal_next_col:
    addi $s0, $s0, 1
    j horizontal_col_loop

next_horizontal_row:
    addi $s1, $s1, 1
    j horizontal_row_loop

horizontal_done:
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    addi $sp, $sp, 20
    jr $ra

# Diagonal match check
check_diagonal_matches:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s1, 1              # row = 1..13

diag_row_loop:
    bgt $s1, 13, diag_done

    li $s0, 4              # col = 4..9

diag_col_loop:
    bgt $s0, 9, next_diag_row

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1      # s2 = display address

    move $a0, $s2
    jal get_color_grid
    move $s3, $v0
    beq $s3, $zero, diag_next_col

    # down-right
    ble $s0, 7, try_down_right
    j try_down_left

try_down_right:
    addi $a0, $s2, 132
    jal get_color_grid
    bne $v0, $s3, try_down_left

    addi $a0, $s2, 264
    jal get_color_grid
    bne $v0, $s3, try_down_left

    move $a0, $s2
    jal mark_match
    addi $a0, $s2, 132
    jal mark_match
    addi $a0, $s2, 264
    jal mark_match

try_down_left:
    bge $s0, 6, do_down_left
    j diag_next_col

do_down_left:
    addi $a0, $s2, 124
    jal get_color_grid
    bne $v0, $s3, diag_next_col

    addi $a0, $s2, 248
    jal get_color_grid
    bne $v0, $s3, diag_next_col

    move $a0, $s2
    jal mark_match
    addi $a0, $s2, 124
    jal mark_match
    addi $a0, $s2, 248
    jal mark_match

diag_next_col:
    addi $s0, $s0, 1
    j diag_col_loop

next_diag_row:
    addi $s1, $s1, 1
    j diag_row_loop

diag_done:
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    addi $sp, $sp, 20
    jr $ra

# Clear matched cells from grid and display
# Return v0 = 1 if anything cleared
clear_matches:
    la $t0, grid
    la $t1, other_grid
    lw $t2, ADDR_DSPL
    li $t3, 0
    li $v0, 0

    li $t4, 4096
clear_loop:
    bge $t3, $t4, clear_finish

    lw $t5, 0($t1)
    beq $t5, $zero, not_clear

    li $v0, 1
    sw $zero, 0($t0)

    add $t6, $t2, $t3
    sw $zero, 0($t6)

not_clear:
    addi $t0, $t0, 4
    addi $t1, $t1, 4
    addi $t3, $t3, 4
    j clear_loop

clear_finish:
    jr $ra

# Drop remaining gems column by column
drop_gems:
    addi $sp, $sp, -8
    sw $ra, 0($sp)
    sw $s0, 4($sp)

    li $s0, 4              # playable columns 4..9

drop_col_loop:
    bgt $s0, 9, drop_done
    move $a0, $s0
    jal drop_one_column
    addi $s0, $s0, 1
    j drop_col_loop

drop_done:
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    addi $sp, $sp, 8
    jr $ra

# Input: a0 = playable column index
drop_one_column:
    addi $sp, $sp, -24
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)

    move $s0, $a0          # s0 = playable column index
    li $s1, 15             # start from bottom row

drop_row_loop:
    blt $s1, 1, drop_col_finish

    # s2 = display address of target cell (col s0, row s1)
    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1

    # if target already occupied, go to next row above
    move $a0, $s2
    jal get_color_grid
    bne $v0, $zero, next_drop

    # search upward for nearest gem
    addi $s3, $s1, -1

find_gem_loop:
    blt $s3, 1, next_drop

    # s4 = display address of candidate source cell
    lw $s4, ADDR_DSPL
    sll $t0, $s0, 2
    add $s4, $s4, $t0
    sll $t1, $s3, 7
    add $s4, $s4, $t1

    move $a0, $s4
    jal get_color_grid
    beq $v0, $zero, continue_find

    # Move color from source s4 to target s2 in grid
    lw $t8, ADDR_DSPL

    sub $t9, $s2, $t8
    la $t0, grid
    add $t0, $t0, $t9
    sw $v0, 0($t0)

    sub $t9, $s4, $t8
    la $t0, grid
    add $t0, $t0, $t9
    sw $zero, 0($t0)

    # Update display
    sw $v0, 0($s2)
    sw $zero, 0($s4)

    # done with this target row
    j next_drop

continue_find:
    addi $s3, $s3, -1
    j find_gem_loop

next_drop:
    addi $s1, $s1, -1
    j drop_row_loop

drop_col_finish:
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    addi $sp, $sp, 24
    jr $ra

draw_preview_panel:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # First clear inside of preview panel to black
    li $t1, 0x000000

    # clear row 1
    addi $a0, $zero, 13
    addi $a1, $zero, 1
    addi $a2, $zero, 4
    jal draw_hor_line

    # clear row 2
    addi $a0, $zero, 13
    addi $a1, $zero, 2
    addi $a2, $zero, 4
    jal draw_hor_line

    # clear row 3
    addi $a0, $zero, 13
    addi $a1, $zero, 3
    addi $a2, $zero, 4
    jal draw_hor_line

    # clear row 4
    addi $a0, $zero, 13
    addi $a1, $zero, 4
    addi $a2, $zero, 4
    jal draw_hor_line

    # Draw the preview vertical column
    la $t0, preview_colors
    lw $t2, ADDR_DSPL

    # top preview gem at col 14 row 1
    addi $t2, $t2, 184

    lw $t1, 0($t0)
    sw $t1, 0($t2)

    lw $t1, 4($t0)
    sw $t1, 128($t2)

    lw $t1, 8($t0)
    sw $t1, 256($t2)

    lw $ra, 0($sp)
    addi $sp, $sp, 4
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