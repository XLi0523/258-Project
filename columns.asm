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
#
# Features implemented:
#   Easy 1  - Gravity (column auto-falls each tick)
#   Easy 2  - Gravity ramps up over time (threshold decreases every 5 gems)
#   Easy 3  - Difficulty selection (1=easy, 2=medium, 3=hard)
#   Easy 6  - Pause / resume with p key
#   Easy 10 - Side panel previewing the next column
#   Hard 5  - Background music (Clotho theme via async MIDI)
#
##############################################################################

    .data
##############################################################################
# Data
##############################################################################
ADDR_DSPL:
    .word 0x10008000
ADDR_KBRD:
    .word 0xffff0000
#red, green, blue, yellow, purple, orange, cyan, pink
colors:
    .word 0x00ff0000, 0x0000ff00, 0x000000ff, 0x00ffff00, 0x00911ca6, 0x00f5691d, 0x0000ffff, 0x00ff69b4

gem_colors:
    .word 0x0, 0x0, 0x0
preview_colors:
    .word 0x0, 0x0, 0x0

#Shape IDs:
#0 = vertical
#1 = L-right
#2 = L-left
current_shape:
    .word 0
preview_shape:
    .word 0

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

# Background music state
music_index:
    .word 0
music_timer:
    .word 0

# Clotho theme (Columns, Sega Genesis) - extracted from clotho.mid
# Track 1 arpeggiated accompaniment, all eighth notes (8 game ticks each)
# Am section: A4-E4-C5-E4 / B4-E4-A4-E4 / G#4-E4-B4-E4 / A4-E4-G#4-E4
# G/D section: G4-D4-B4-D4 / A4-D4-G4-D4 / F#4-D4-G4-D4 / A4-D4-G4-D4
melody_pitches:
    .word 69, 64, 72, 64, 71, 64, 69, 64   # Am arpeggio
    .word 68, 64, 71, 64, 69, 64, 68, 64   # E/G# arpeggio
    .word 67, 62, 71, 62, 69, 62, 67, 62   # G/D arpeggio
    .word 66, 62, 67, 62, 69, 62, 67, 62   # D/F# -> G -> Am resolve
melody_length:
    .word 32
melody_note_dur:
    .word 8                                  # constant: 8 ticks per note (240 ms)

    .text
    .globl main

##############################################################################
# Milestone 1: Draw the scene
##############################################################################
main:
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

    addi $a0, $zero, 12
    addi $a1, $zero, 0
    addi $a2, $zero, 6
    jal draw_hor_line
    addi $a0, $zero, 12
    addi $a1, $zero, 6
    addi $a2, $zero, 6
    jal draw_hor_line
    addi $a0, $zero, 12
    addi $a1, $zero, 1
    addi $a2, $zero, 5
    jal draw_ver_line
    addi $a0, $zero, 17
    addi $a1, $zero, 1
    addi $a2, $zero, 5
    jal draw_ver_line

    li $v0, 4
    la $a0, start_string
    syscall

    j wait_start

##############################################################################
# Easy 3: Difficulty selection
##############################################################################
wait_start:
    lw $t9, ADDR_KBRD
    lw $t8, 0($t9)
    beq $t8, 1, start_input
    j wait_start

start_input:
    lw $t2, 4($t9)
    beq $t2, 0x31, select_easy
    beq $t2, 0x32, select_medium
    beq $t2, 0x33, select_hard
    beq $t2, 0x71, respond_to_q
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

    # Initialize music: index=0, timer=1 (plays first note immediately)
    sw $zero, music_index
    li $t0, 1
    sw $t0, music_timer

    lw $t9, ADDR_KBRD
    lw $t2, 4($t9)

    j game_loop

##############################################################################
# Milestone 2: Game loop, movement, controls
# Easy 1: Gravity
##############################################################################
game_loop:
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
    jal music_tick

    li $v0, 32
    li $a0, 30
    syscall

    j game_loop

keyboard_input:
    lw $t2, 4($t9)
    beq $t2, 0x61, respond_to_a  # a
    beq $t2, 0x64, respond_to_d  # d
    beq $t2, 0x73, respond_to_s  # s
    beq $t2, 0x77, respond_to_w  # w
    beq $t2, 0x71, respond_to_q  # q
    beq $t2, 0x70, respond_to_p  # p
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

# Soft drop: reset gravity counter and move down immediately
respond_to_s:
    la $t0, gravity_counter
    sw $zero, 0($t0)
    jal check_bottom_gem_collision
    beq $v0, $zero, gem_landed
    jal delete_gem
    addi $t7, $t7, 128
    jal draw_gem
    j gravity_tick

# Shuffle: cycle the 3 gem colors downward
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

##############################################################################
# Easy 6: Pause / resume
##############################################################################
respond_to_p:
    li $v0, 4
    la $a0, paused_string
    syscall
    jal draw_pause_text

pause_loop:
    lw $t9, ADDR_KBRD
    lw $t8, 0($t9)
    beq $t8, $zero, pause_loop
    lw $t2, 4($t9)
    bne $t2, 0x70, pause_loop

    jal erase_pause_text
    li $v0, 4
    la $a0, resumed_string
    syscall
    j gravity_tick

respond_to_q:
    li $v0, 10
    syscall

##############################################################################
# Milestone 3: Landing, matching, game over
# Easy 2: Gravity ramp-up
##############################################################################
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
    la $t9, preview_shape
    lw $t8, 0($t9)
    
    lw $t0, ADDR_DSPL
    
    #check top spawn call
    addi $a0, $t0, 152
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    
    #check middle spawn call
    addi $a0, $t0, 280
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    
    beq $t8, $zero, check_spawn_vertical
    beq $t8, 1, check_spawn_L_right
    j check_spawn_L_left

check_spawn_vertical:
    addi $a0, $t0, 408
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    j spawn_ok

check_spawn_L_right:
    addi $a0, $t0, 284
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    j spawn_ok

check_spawn_L_left:
    addi $a0, $t0, 276
    jal get_color_grid
    bne $v0, $zero, spawn_blocked
    
spawn_ok:    
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

##############################################################################
# Drawing helpers
##############################################################################

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
    li $a1, 8
    syscall
    la $t4, colors
    sll $t5, $a0, 2
    addu $t4, $t4, $t5
    lw $t1, 0($t4)
    jr $ra

# Generate a random shape ID: 0, 1, 2
gem_shape:
    li $v0, 42
    li $a0, 0
    li $a1, 3
    syscall
    move $v0, $a0
    jr $ra

# Copy preview into gem_colors, generate new preview, update panel
draw_new_gem:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    #Copy preview shape into current shape
    la $t0, preview_shape
    lw $t1, 0($t0)
    la $t2, current_shape
    sw $t1, 0($t2)
    
    #Copy preview colors into current colors
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
    la $t9, current_shape
    lw $t8, 0($t9)        #current shape
    
    #draw top gem
    lw $t1, 0($t6)
    sw $t1, 0($t7)
    
    beq $t8, $zero, draw_gem_vertical
    beq $t8, 1, draw_gem_L_right
    
    #shape 2 = L-left
draw_gem_L_left:
    lw $t1, 4($t6)
    sw $t1, 128($t7)
    lw $t1, 8($t6)
    sw $t1, 124($t7)
    jr $ra

draw_gem_L_right:
    lw $t1, 4($t6)
    sw $t1, 128($t7)
    lw $t1, 8($t6)
    sw $t1, 132($t7)
    jr $ra

draw_gem_vertical:
    lw $t1, 4($t6)
    sw $t1, 128($t7)
    lw $t1, 8($t6)
    sw $t1, 256($t7)
    jr $ra
    
delete_gem:
    li $t1, 0x000000
    la $t9, current_shape
    lw $t8, 0($t9)
    
    #erase top gem
    sw $t1, 0($t7)
    
    beq $t8, $zero, delete_vertical
    beq $t8, 1, delete_L_right
    
    #shape 2 = L-left
delete_L_left:
    sw $t1, 128($t7)
    sw $t1, 124($t7)
    jr $ra

delete_L_right:
    sw $t1, 128($t7)
    sw $t1, 132($t7)
    jr $ra

delete_vertical:
    sw $t1, 128($t7)
    sw $t1, 256($t7)
    jr $ra
# a0=col, a1=row, a2=length, $t1=color
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

# a0=col, a1=row, a2=length, $t1=color
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

##############################################################################
# Grid storage helpers
##############################################################################

store_gems_in_grid:
    addi $sp, $sp, -8
    sw $ra, 0($sp)
    sw $t0, 4($sp)

    la $t6, gem_colors
    lw $t0, ADDR_DSPL
    sub $t2, $t7, $t0
    la $t3, grid
    add $t3, $t3, $t2
    
    la $t9, current_shape
    lw $t8, 0($t9)

    #Store top gem
    lw $t1, 0($t6)
    sw $t1, 0($t3)

    beq $t8, $zero, store_vertical
    beq $t8, 1, store_L_right
    
    #Shape 2 = L-left
store_L_left:
    lw $t1, 4($t6)
    sw $t1, 128($t3)
    lw $t1, 8($t6)
    sw $t1, 124($t3)
    j store_done

store_L_right:
    lw $t1, 4($t6)
    sw $t1, 128($t3)
    lw $t1, 8($t6)
    sw $t1, 132($t3)
    j store_done
    
store_vertical:
    lw $t1, 4($t6)
    sw $t1, 128($t3)
    lw $t1, 8($t6)
    sw $t1, 256($t3)
    
store_done:
    lw $ra, 0($sp)
    lw $t0, 4($sp)
    addi $sp, $sp, 8
    jr $ra
# Return color at display address $a0 from the grid array
get_color_grid:
    lw $t0, ADDR_DSPL
    sub $t2, $a0, $t0
    la $t3, grid
    add $t3, $t3, $t2
    lw $v0, 0($t3)
    jr $ra

##############################################################################
# Collision detection helpers
##############################################################################

check_left_collision:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, ADDR_DSPL
    sub $t1, $t7, $t0
    andi $t2, $t1, 0x7f
    srl $t2, $t2, 2

    la $t9, current_shape
    lw $t8, 0($t9)
    
    li $t3, 4
    beq $t8, 2, left_Lleft_bound
    j left_bound_check

left_Lleft_bound:
    li $t3, 5
    
left_bound_check:    
    ble $t2, $t3, cannot_move_left

    #left of top
    addi $t4, $t7, -4
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left

    beq $t8, $zero, left_vertical_gems
    beq $t8, 1, left_Lright_gems
    j left_Lleft_gems

left_vertical_gems:    
    addi $t4, $t7, 124
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left

    addi $t4, $t7, 252
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left
    j left_ok

left_Lright_gems:
    addi $t4, $t7, 124
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left
    
    addi $t4, $t7, 128
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left
    j left_ok

left_Lleft_gems:
    addi $t4, $t7, 124
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left
    
    addi $t4, $t7, 120
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_left
    j left_ok
    
left_ok:
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

    la $t9, current_shape
    lw $t8, 0($t9)

    li $t3, 9
    beq $t8, 1, right_Lright_bound
    j right_bound_check
 
right_Lright_bound:
    li $t3, 8
 
right_bound_check:    
    bge $t2, $t3, cannot_move_right

    #right of top
    addi $t4, $t7, 4
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    
    beq $t8, $zero, right_vertical_gems
    beq $t8, 1, right_Lright_gems
    j right_Lleft_gems

right_vertical_gems:
    addi $t4, $t7, 132
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right

    addi $t4, $t7, 260
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    j right_ok

right_Lright_gems:
    addi $t4, $t7, 132
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    
    addi $t4, $t7, 136
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    j right_ok
    
right_Lleft_gems:
    addi $t4, $t7, 128
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    
    addi $t4, $t7, 132
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_right
    j right_ok

right_ok:
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

    la $t9, current_shape
    lw $t8, 0($t9)

    li $t3, 13
    beq $t8, $zero, bottom_row_bound
    li $t3, 14

bottom_row_bound:    
    bge $t2, $t3, cannot_move_down
    
    beq $t8, $zero, bottom_vertical_gems
    beq $t8, 1, bottom_Lright_gems
    j bottom_Lleft_gems

bottom_vertical_gems:
    addi $t4, $t7, 384
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down
    j bottom_ok

bottom_Lright_gems:
    addi $t4, $t7, 256
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down
    
    addi $t4, $t7, 260
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down
    j bottom_ok
    
bottom_Lleft_gems:
    addi $t4, $t7, 252
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down
    
    addi $t4, $t7, 256
    move $a0, $t4
    jal get_color_grid
    bne $v0, $zero, cannot_move_down
    
bottom_ok:
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
# Matching helpers
##############################################################################

# Scan vertical, horizontal, and diagonal for 3-in-a-row
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

mark_match:
    lw $t0, ADDR_DSPL
    sub $t1, $a0, $t0
    la $t2, other_grid
    add $t2, $t2, $t1
    li $t3, 1
    sw $t3, 0($t2)
    jr $ra

check_vertical_matches:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s0, 4

vertical_col_loop:
    bgt $s0, 9, vertical_done

    li $s1, 1

vertical_row_loop:
    bgt $s1, 13, next_vertical_col

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1

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

check_horizontal_match:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s1, 1

horizontal_row_loop:
    bgt $s1, 15, horizontal_done

    li $s0, 4

horizontal_col_loop:
    bgt $s0, 7, next_horizontal_row

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1

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

check_diagonal_matches:
    addi $sp, $sp, -20
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)

    li $s1, 1

diag_row_loop:
    bgt $s1, 13, diag_done

    li $s0, 4

diag_col_loop:
    bgt $s0, 9, next_diag_row

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1

    move $a0, $s2
    jal get_color_grid
    move $s3, $v0
    beq $s3, $zero, diag_next_col

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

##############################################################################
# Clear matches and drop gems
##############################################################################

# Return v0=1 if anything was cleared
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

drop_gems:
    addi $sp, $sp, -8
    sw $ra, 0($sp)
    sw $s0, 4($sp)

    li $s0, 4

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

# For each empty cell, find the nearest gem above and move it down
drop_one_column:
    addi $sp, $sp, -24
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)

    move $s0, $a0
    li $s1, 15

drop_row_loop:
    blt $s1, 1, drop_col_finish

    lw $s2, ADDR_DSPL
    sll $t0, $s0, 2
    add $s2, $s2, $t0
    sll $t1, $s1, 7
    add $s2, $s2, $t1

    move $a0, $s2
    jal get_color_grid
    bne $v0, $zero, next_drop

    addi $s3, $s1, -1

find_gem_loop:
    blt $s3, 1, next_drop

    lw $s4, ADDR_DSPL
    sll $t0, $s0, 2
    add $s4, $s4, $t0
    sll $t1, $s3, 7
    add $s4, $s4, $t1

    move $a0, $s4
    jal get_color_grid
    beq $v0, $zero, continue_find

    lw $t8, ADDR_DSPL

    sub $t9, $s2, $t8
    la $t0, grid
    add $t0, $t0, $t9
    sw $v0, 0($t0)

    sub $t9, $s4, $t8
    la $t0, grid
    add $t0, $t0, $t9
    sw $zero, 0($t0)

    sw $v0, 0($s2)
    sw $zero, 0($s4)

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

##############################################################################
# Preview panel (Easy 10)
##############################################################################

init_preview:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    #Generate preview shape
    jal gem_shape
    la $t0, preview_shape
    sw $v0, 0($t0)

    #Generate preview colors
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

draw_preview_panel:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $t1, 0x000000

    addi $a0, $zero, 13
    addi $a1, $zero, 1
    addi $a2, $zero, 4
    jal draw_hor_line

    addi $a0, $zero, 13
    addi $a1, $zero, 2
    addi $a2, $zero, 4
    jal draw_hor_line

    addi $a0, $zero, 13
    addi $a1, $zero, 3
    addi $a2, $zero, 4
    jal draw_hor_line

    addi $a0, $zero, 13
    addi $a1, $zero, 4
    addi $a2, $zero, 4
    jal draw_hor_line

    la $t0, preview_colors
    la $t9, preview_shape
    lw $t8, 0($t9)
    
    lw $t2, ADDR_DSPL
    addi $t2, $t2, 184        #preview top position

    #top gem
    lw $t1, 0($t0)
    sw $t1, 0($t2)

    beq $t8, $zero, preview_vertical
    beq $t8, 1, preview_L_right
    
    #shape 2 = L-left
preview_L_left:
    lw $t1, 4($t0)
    sw $t1, 128($t2)
    lw $t1, 8($t0)
    sw $t1, 124($t2)
    j preview_done

preview_L_right:
    lw $t1, 4($t0)
    sw $t1, 128($t2)
    lw $t1, 8($t0)
    sw $t1, 132($t2)
    j preview_done

preview_vertical:
    lw $t1, 4($t0)
    sw $t1, 128($t2)
    lw $t1, 8($t0)
    sw $t1, 256($t2)

preview_done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

##############################################################################
# Hard 5: Background music (Clotho theme via async MIDI)
##############################################################################

music_tick:
    la $t0, music_timer
    lw $t1, 0($t0)
    addi $t1, $t1, -1
    sw $t1, 0($t0)
    bgtz $t1, music_done       # note still playing, nothing to do

    # Timer expired -- reset timer and load next note
    lw $t5, melody_note_dur    # constant duration (8 ticks)
    la $t0, music_timer
    sw $t5, 0($t0)

    la $t0, music_index
    lw $t1, 0($t0)

    la $t2, melody_pitches
    sll $t3, $t1, 2
    add $t2, $t2, $t3
    lw $t4, 0($t2)             # $t4 = pitch

    # Advance index (wrap around to loop)
    addi $t1, $t1, 1
    lw $t2, melody_length
    blt $t1, $t2, music_no_wrap
    li $t1, 0
music_no_wrap:
    sw $t1, 0($t0)

    # syscall 31: async MIDI out
    # $a0 = pitch, $a1 = duration ms, $a2 = instrument, $a3 = volume
    move $a0, $t4
    li $a1, 240                 # 8 ticks * 30 ms = 240 ms
    li $a2, 19                  # Church Organ (matches original MIDI)
    li $a3, 80                  # volume
    li $v0, 31
    syscall

music_done:
    jr $ra

##############################################################################
# Pause overlay: draw / erase "PAUSED" on the bitmap display
##############################################################################

draw_pause_text:
    lw $t0, ADDR_DSPL
    li $t1, 0x00ffffff

    # P (col 7-9): ##. / #.# / ##. / #.. / #..
    sw $t1, 2588($t0)
    sw $t1, 2592($t0)
    sw $t1, 2716($t0)
    sw $t1, 2724($t0)
    sw $t1, 2844($t0)
    sw $t1, 2848($t0)
    sw $t1, 2972($t0)
    sw $t1, 3100($t0)

    # A (col 11-13): .#. / #.# / ### / #.# / #.#
    sw $t1, 2608($t0)
    sw $t1, 2732($t0)
    sw $t1, 2740($t0)
    sw $t1, 2860($t0)
    sw $t1, 2864($t0)
    sw $t1, 2868($t0)
    sw $t1, 2988($t0)
    sw $t1, 2996($t0)
    sw $t1, 3116($t0)
    sw $t1, 3124($t0)

    # U (col 15-17): #.# / #.# / #.# / #.# / .#.
    sw $t1, 2620($t0)
    sw $t1, 2628($t0)
    sw $t1, 2748($t0)
    sw $t1, 2756($t0)
    sw $t1, 2876($t0)
    sw $t1, 2884($t0)
    sw $t1, 3004($t0)
    sw $t1, 3012($t0)
    sw $t1, 3136($t0)

    # S (col 19-21): .## / #.. / .#. / ..# / ##.
    sw $t1, 2640($t0)
    sw $t1, 2644($t0)
    sw $t1, 2764($t0)
    sw $t1, 2896($t0)
    sw $t1, 3028($t0)
    sw $t1, 3148($t0)
    sw $t1, 3152($t0)

    # E (col 23-25): ### / #.. / ##. / #.. / ###
    sw $t1, 2652($t0)
    sw $t1, 2656($t0)
    sw $t1, 2660($t0)
    sw $t1, 2780($t0)
    sw $t1, 2908($t0)
    sw $t1, 2912($t0)
    sw $t1, 3036($t0)
    sw $t1, 3164($t0)
    sw $t1, 3168($t0)
    sw $t1, 3172($t0)

    # D (col 27-29): ##. / #.# / #.# / #.# / ##.
    sw $t1, 2668($t0)
    sw $t1, 2672($t0)
    sw $t1, 2796($t0)
    sw $t1, 2804($t0)
    sw $t1, 2924($t0)
    sw $t1, 2932($t0)
    sw $t1, 3052($t0)
    sw $t1, 3060($t0)
    sw $t1, 3180($t0)
    sw $t1, 3184($t0)

    jr $ra

erase_pause_text:
    lw $t0, ADDR_DSPL
    li $t1, 0x000000

    # Erase 23 columns x 5 rows starting at offset 2588
    # Row 0 (offsets 2588 .. 2676)
    sw $t1, 2588($t0)
    sw $t1, 2592($t0)
    sw $t1, 2596($t0)
    sw $t1, 2600($t0)
    sw $t1, 2604($t0)
    sw $t1, 2608($t0)
    sw $t1, 2612($t0)
    sw $t1, 2616($t0)
    sw $t1, 2620($t0)
    sw $t1, 2624($t0)
    sw $t1, 2628($t0)
    sw $t1, 2632($t0)
    sw $t1, 2636($t0)
    sw $t1, 2640($t0)
    sw $t1, 2644($t0)
    sw $t1, 2648($t0)
    sw $t1, 2652($t0)
    sw $t1, 2656($t0)
    sw $t1, 2660($t0)
    sw $t1, 2664($t0)
    sw $t1, 2668($t0)
    sw $t1, 2672($t0)
    sw $t1, 2676($t0)
    # Row 1 (offsets 2716 .. 2804)
    sw $t1, 2716($t0)
    sw $t1, 2720($t0)
    sw $t1, 2724($t0)
    sw $t1, 2728($t0)
    sw $t1, 2732($t0)
    sw $t1, 2736($t0)
    sw $t1, 2740($t0)
    sw $t1, 2744($t0)
    sw $t1, 2748($t0)
    sw $t1, 2752($t0)
    sw $t1, 2756($t0)
    sw $t1, 2760($t0)
    sw $t1, 2764($t0)
    sw $t1, 2768($t0)
    sw $t1, 2772($t0)
    sw $t1, 2776($t0)
    sw $t1, 2780($t0)
    sw $t1, 2784($t0)
    sw $t1, 2788($t0)
    sw $t1, 2792($t0)
    sw $t1, 2796($t0)
    sw $t1, 2800($t0)
    sw $t1, 2804($t0)
    # Row 2 (offsets 2844 .. 2932)
    sw $t1, 2844($t0)
    sw $t1, 2848($t0)
    sw $t1, 2852($t0)
    sw $t1, 2856($t0)
    sw $t1, 2860($t0)
    sw $t1, 2864($t0)
    sw $t1, 2868($t0)
    sw $t1, 2872($t0)
    sw $t1, 2876($t0)
    sw $t1, 2880($t0)
    sw $t1, 2884($t0)
    sw $t1, 2888($t0)
    sw $t1, 2892($t0)
    sw $t1, 2896($t0)
    sw $t1, 2900($t0)
    sw $t1, 2904($t0)
    sw $t1, 2908($t0)
    sw $t1, 2912($t0)
    sw $t1, 2916($t0)
    sw $t1, 2920($t0)
    sw $t1, 2924($t0)
    sw $t1, 2928($t0)
    sw $t1, 2932($t0)
    # Row 3 (offsets 2972 .. 3060)
    sw $t1, 2972($t0)
    sw $t1, 2976($t0)
    sw $t1, 2980($t0)
    sw $t1, 2984($t0)
    sw $t1, 2988($t0)
    sw $t1, 2992($t0)
    sw $t1, 2996($t0)
    sw $t1, 3000($t0)
    sw $t1, 3004($t0)
    sw $t1, 3008($t0)
    sw $t1, 3012($t0)
    sw $t1, 3016($t0)
    sw $t1, 3020($t0)
    sw $t1, 3024($t0)
    sw $t1, 3028($t0)
    sw $t1, 3032($t0)
    sw $t1, 3036($t0)
    sw $t1, 3040($t0)
    sw $t1, 3044($t0)
    sw $t1, 3048($t0)
    sw $t1, 3052($t0)
    sw $t1, 3056($t0)
    sw $t1, 3060($t0)
    # Row 4 (offsets 3100 .. 3188)
    sw $t1, 3100($t0)
    sw $t1, 3104($t0)
    sw $t1, 3108($t0)
    sw $t1, 3112($t0)
    sw $t1, 3116($t0)
    sw $t1, 3120($t0)
    sw $t1, 3124($t0)
    sw $t1, 3128($t0)
    sw $t1, 3132($t0)
    sw $t1, 3136($t0)
    sw $t1, 3140($t0)
    sw $t1, 3144($t0)
    sw $t1, 3148($t0)
    sw $t1, 3152($t0)
    sw $t1, 3156($t0)
    sw $t1, 3160($t0)
    sw $t1, 3164($t0)
    sw $t1, 3168($t0)
    sw $t1, 3172($t0)
    sw $t1, 3176($t0)
    sw $t1, 3180($t0)
    sw $t1, 3184($t0)
    sw $t1, 3188($t0)

    jr $ra
