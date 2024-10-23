
add wave /tb_relobi_dec/i_dut/*

# Encoder
add wave -group encoder /tb_relobi_dec/i_dut/i_encoder/*

add wave -group encoder -group addr_enc /tb_relobi_dec/i_dut/i_encoder/i_addr_enc/*
add wave -group encoder -group wdata_enc /tb_relobi_dec/i_dut/i_encoder/i_wdata_enc/*
add wave -group encoder -group aother_enc /tb_relobi_dec/i_dut/i_encoder/i_a_remaining_enc/*

add wave -group encoder -group rdata_dec /tb_relobi_dec/i_dut/i_encoder/i_rdata_dec/*
add wave -group encoder -group rother_enc /tb_relobi_dec/i_dut/i_encoder/i_r_remaining_dec/*

# Demux
add wave -group demux sim:/tb_relobi_dec/i_dut/i_demux/*

add wave -group demux -group rvoter sim:/tb_relobi_dec/i_dut/i_demux/i_r_vote/*
for {set i 0} {$i < 3} {incr i} {
	add wave -group demux -group tmr_${i} -divider select
	add wave -group demux -group tmr_${i} sim:/tb_relobi_dec/i_dut/i_demux/gen_tmr_state[$i]/i_select_vote/*
	add wave -group demux -group tmr_${i} -divider counter
	add wave -group demux -group tmr_${i} sim:/tb_relobi_dec/i_dut/i_demux/gen_tmr_state[$i]/i_select_vote/*
}

# Decoder
for {set i 0} {$i < 8} {incr i} {
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/*
	add wave -group decoder_${i} -divider addr
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/i_addr_dec/*
	add wave -group decoder_${i} -divider wdata
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/i_wdata_dec/*
	add wave -group decoder_${i} -divider a_other
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/i_a_remaining_dec/*
	add wave -group decoder_${i} -divider rdata
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/i_rdata_enc/*
	add wave -group decoder_${i} -divider r_other
	add wave -group decoder_${i} sim:/tb_relobi_dec/i_dut/gen_relobi_decoder[$i]/i_decoder/i_r_remaining_enc/*
}
