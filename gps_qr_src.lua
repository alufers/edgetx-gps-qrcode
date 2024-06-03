
--- EdgeTX lua script for displaying the GPS location of a model as a QR code,
--- which can be scanned by a smartphone to open the location in the map app.
---
--- This script is based on the luaqrcode library by speedata. The same 3-clause BSD license applies.
---
--- Adaptation & optimization by alufers (github.com/alufers)
--- The following things were changed compared to the luaqrcode library:
---    - Added some glue code to make it work as an EdgeTX telemetry script.
---         - It reads a telemetry field named "GPS" and generates a qr code with the data: geo:<lat>,<lon>
---         - The QR code can be read by modern Android and iOS devices to open the location in the map app.
---    - Removed the ability to generate numeric, alphanumeric, kanji QR codes.
---    - Removed error correction levels other than L.
---    - Removed the ability to generate QR codes with version higher than 11 (ie. 61x61 px).
---    - Respective lookup tables were shrunk or removed to save memory.
---    - Removed the use of closures and gsub
---    - Inlined some functions and removed some unnecessary checks and assertions
---    - Updated for lua 5.2 (use bit32)
---    - NOTE: some comments may be outdated due to the changes above
---
--- See the original license information for luaqrcode below:
---
--- The qrcode library is licensed under the 3-clause BSD license (aka "new BSD")
--- To get in contact with the author, mail to <gundlach@speedata.de>.
---
--- Please report bugs on the [github project page](http://speedata.github.io/luaqrcode/).
-- Copyright (c) 2012-2020, Patrick Gundlach and contributors, see https://github.com/speedata/luaqrcode
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--	 * Redistributions of source code must retain the above copyright
--	   notice, this list of conditions and the following disclaimer.
--	 * Redistributions in binary form must reproduce the above copyright
--	   notice, this list of conditions and the following disclaimer in the
--	   documentation and/or other materials provided with the distribution.
--	 * Neither the name of SPEEDATA nor the
--	   names of its contributors may be used to endorse or promote products
--	   derived from this software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL SPEEDATA GMBH BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


--- Overall workflow
--- ================
--- The steps to generate the qrcode, assuming we already have the codeword:
---
--- 1. Determine version (=size in QR code terminology)
--- 1. Encode data
--- 1. Arrange data and calculate error correction code
--- 1. Generate 8 matrices with different masks and calculate the penalty
--- 1. Return qrcode with least penalty
---
--- Each step is of course more or less complex and needs further description

--- Helper functions
--- ================
---
--- We start with some helper functions

-- To calculate xor we need to do that bitwise. This helper table speeds up the num-to-bit
-- part a bit (no pun intended)



local function binary(num, bits)
    -- returns a table of bits, least significant first.
    local t = ""
   
    while num>0 do
        rest=num%2
        t=t..rest
        num=math.floor((num-rest)/2)
    end
    for i = #t+1, bits do -- fill empty bits with 0
        t = t .. "0"
    end
    return string.reverse(t)
end





--- Capacity of QR codes
--- --------------------
--- The capacity is calculated as follow: \\(\text{Number of data bits} = \text{number of codewords} * 8\\).
--- The number of data bits is now reduced by 4 (the mode indicator) and the length string,
--- that varies between 8 and 16, depending on the version and the mode. The
--- remaining capacity is multiplied by the amount of data per bit string (numeric: 3, alphanumeric: 2, other: 1)
--- and divided by the length of the bit string (numeric: 10, alphanumeric: 11, binary: 8, kanji: 13).
--- Then the floor function is applied to the result:
--- $$\Big\lfloor \frac{( \text{#data bits} - 4 - \text{length string}) * \text{data per bit string}}{\text{length of the bit string}} \Big\rfloor$$
---
--- There is one problem remaining. The length string depends on the version,
--- and the version depends on the length string. But we take this into account when calculating the
--- the capacity, so this is not really a problem here.

-- The capacity (number of codewords) of each version (1-40) for error correction levels 1-4 (LMQH).
-- The higher the ec level, the lower the capacity of the version. Taken from spec, tables 7-11.

local capacity = {19, 34, 55, 80, 108, 136, 156, 194, 232, 274, 324 }



--- Step 2: Encode data
--- ===================

--- There are several ways to encode the data. We currently support only binary.
--- We already chose the encoding (a.k.a. mode) in the first step, so we need to apply the mode to the
--- codeword.
---
--- **Binary**: take one octet and encode it in 8 bits







--- Step 3: Organize data and calculate error correction code
--- =======================================================
--- The data in the qrcode is not encoded linearly. For example code 5-H has four blocks, the first two blocks
--- contain 11 codewords and 22 error correction codes each, the second block contain 12 codewords and 22 ec codes each.
--- We just take the table from the spec and don't calculate the blocks ourself. The table `ecblocks` contains this info.
---
--- During the phase of splitting the data into codewords, we do the calculation for error correction codes. This step involves
--- polynomial division. Find a math book from school and follow the code here :)

--- ### Reed Solomon error correction
--- Now this is the slightly ugly part of the error correction. We start with log/antilog tables
-- https://codyplanteen.com/assets/rs/gf256_log_antilog.pdf
local alpha_int = {
	[0] = 1,
	  2,   4,   8,  16,  32,  64, 128,  29,  58, 116, 232, 205, 135,  19,  38,  76,
	152,  45,  90, 180, 117, 234, 201, 143,   3,   6,  12,  24,  48,  96, 192, 157,
	 39,  78, 156,  37,  74, 148,  53, 106, 212, 181, 119, 238, 193, 159,  35,  70,
	140,   5,  10,  20,  40,  80, 160,  93, 186, 105, 210, 185, 111, 222, 161,  95,
	190,  97, 194, 153,  47,  94, 188, 101, 202, 137,  15,  30,  60, 120, 240, 253,
	231, 211, 187, 107, 214, 177, 127, 254, 225, 223, 163,  91, 182, 113, 226, 217,
	175,  67, 134,  17,  34,  68, 136,  13,  26,  52, 104, 208, 189, 103, 206, 129,
	 31,  62, 124, 248, 237, 199, 147,  59, 118, 236, 197, 151,  51, 102, 204, 133,
	 23,  46,  92, 184, 109, 218, 169,  79, 158,  33,  66, 132,  21,  42,  84, 168,
	 77, 154,  41,  82, 164,  85, 170,  73, 146,  57, 114, 228, 213, 183, 115, 230,
	209, 191,  99, 198, 145,  63, 126, 252, 229, 215, 179, 123, 246, 241, 255, 227,
	219, 171,  75, 150,  49,  98, 196, 149,  55, 110, 220, 165,  87, 174,  65, 130,
	 25,  50, 100, 200, 141,   7,  14,  28,  56, 112, 224, 221, 167,  83, 166,  81,
	162,  89, 178, 121, 242, 249, 239, 195, 155,  43,  86, 172,  69, 138,   9,  18,
	 36,  72, 144,  61, 122, 244, 245, 247, 243, 251, 235, 203, 139,  11,  22,  44,
	 88, 176, 125, 250, 233, 207, 131,  27,  54, 108, 216, 173,  71, 142,   0,   0
}

local int_alpha = {
	[0] = 256, -- special value
	0,   1,  25,   2,  50,  26, 198,   3, 223,  51, 238,  27, 104, 199,  75,   4,
	100, 224,  14,  52, 141, 239, 129,  28, 193, 105, 248, 200,   8,  76, 113,   5,
	138, 101,  47, 225,  36,  15,  33,  53, 147, 142, 218, 240,  18, 130,  69,  29,
	181, 194, 125, 106,  39, 249, 185, 201, 154,   9, 120,  77, 228, 114, 166,   6,
	191, 139,  98, 102, 221,  48, 253, 226, 152,  37, 179,  16, 145,  34, 136,  54,
	208, 148, 206, 143, 150, 219, 189, 241, 210,  19,  92, 131,  56,  70,  64,  30,
	 66, 182, 163, 195,  72, 126, 110, 107,  58,  40,  84, 250, 133, 186,  61, 202,
	 94, 155, 159,  10,  21, 121,  43,  78, 212, 229, 172, 115, 243, 167,  87,   7,
	112, 192, 247, 140, 128,  99,  13, 103,  74, 222, 237,  49, 197, 254,  24, 227,
	165, 153, 119,  38, 184, 180, 124,  17,  68, 146, 217,  35,  32, 137,  46,  55,
	 63, 209,  91, 149, 188, 207, 205, 144, 135, 151, 178, 220, 252, 190,  97, 242,
	 86, 211, 171,  20,  42,  93, 158, 132,  60,  57,  83,  71, 109,  65, 162,  31,
	 45,  67, 216, 183, 123, 164, 118, 196,  23,  73, 236, 127,  12, 111, 246, 108,
	161,  59,  82,  41, 157,  85, 170, 251,  96, 134, 177, 187, 204,  62,  90, 203,
	 89,  95, 176, 156, 169, 160,  81,  11, 245,  22, 235, 122, 117,  44, 215,  79,
	174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234, 168,  80,  88, 175
}

-- We only need the polynomial generators for block sizes 7, 10, 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, and 30. Version
-- 2 of the qr codes don't need larger ones (as opposed to version 1). The table has the format x^1*ɑ^21 + x^2*a^102 ...
local generator_polynomial = {
	 [7] = { 21, 102, 238, 149, 146, 229,  87,   0}, -- ok
	[10] = { 45,  32,  94,  64,  70, 118,  61,  46,  67, 251,   0 }, -- ok
	-- [13] = { 78, 140, 206, 218, 130, 104, 106, 100,  86, 100, 176, 152,  74,   0 }, 
	[15] = {105,  99,   5, 124, 140, 237,  58,  58,  51,  37, 202,  91,  61, 183,   8,   0}, -- ok
	-- [16] = {120, 225, 194, 182, 169, 147, 191,  91,   3,  76, 161, 102, 109, 107, 104, 120,   0},
	[17] = {136, 163, 243,  39, 150,  99,  24, 147, 214, 206, 123, 239,  43,  78, 206, 139,  43,   0},
	[18] = {153,  96,  98,   5, 179, 252, 148, 152, 187,  79, 170, 118,  97, 184,  94, 158, 234, 215,   0}, -- ok
	[20] = {190, 188, 212, 212, 164, 156, 239,  83, 225, 221, 180, 202, 187,  26, 163,  61,  50,  79,  60,  17,   0},  --ok
	-- [22] = {231, 165, 105, 160, 134, 219,  80,  98, 172,   8,  74, 200,  53, 221, 109,  14, 230,  93, 242, 247, 171, 210,   0},
	[24] = { 21, 227,  96,  87, 232, 117,   0, 111, 218, 228, 226, 192, 152, 169, 180, 159, 126, 251, 117, 211,  48, 135, 121, 229,   0}, --ok
	[26] = { 70, 218, 145, 153, 227,  48, 102,  13, 142, 245,  21, 161,  53, 165,  28, 111, 201, 145,  17, 118, 182, 103,   2, 158, 125, 173,   0}, --ok
	-- [28] = {123,   9,  37, 242, 119, 212, 195,  42,  87, 245,  43,  21, 201, 232,  27, 205, 147, 195, 190, 110, 180, 108, 234, 224, 104, 200, 223, 168,   0},
	[30] = {180, 192,  40, 238, 216, 251,  37, 156, 130, 224, 193, 226, 173,  42, 125, 222,  96, 239,  86, 110,  48,  50, 182, 179,  31, 216, 152, 145, 173, 41, 0}} -- ok



--- These converter functions use the log/antilog table above.
--- We could have created the table programatically, but I like fixed tables.
-- Convert polynominal in int notation to alpha notation.
-- local function convert_to_alpha( tab )
-- 	local new_tab = {}
-- 	for i=0,#tab do
-- 		new_tab[i] = int_alpha[tab[i]]
-- 	end
-- 	return new_tab
-- end

-- Convert polynominal in alpha notation to int notation.
local function convert_to_int(tab)
	local new_tab = {}
	for i=0,#tab do
		new_tab[i] = alpha_int[tab[i]]
	end
	return new_tab
end

-- That's the heart of the error correction calculation.
-- data must be a string
local function calculate_error_correction(data,num_ec_codewords)

    -- Turn a binary string of length 8*x into a table size x of numbers.
	local mp = {}
    for i=1,#data,8 do
        mp[#mp+1] = tonumber(string.sub(data,i,i+7),2)
    end

	local len_message = #mp

	local highest_exponent = len_message + num_ec_codewords - 1
	local gp_alpha,tmp
	local he
	local gp_int, mp_alpha
	local mp_int = {}
	-- create message shifted to left (highest exponent)
	for i=1,len_message do
		mp_int[highest_exponent - i + 1] = mp[i]
	end
	for i=1,highest_exponent - len_message do
		mp_int[i] = 0
	end
	mp_int[0] = 0

	while highest_exponent >= num_ec_codewords do
		-- mp_alpha = convert_to_alpha(mp_int)
		-- BEGIN convert_to_alpha
		mp_alpha = {}
		for i=0,#mp_int do
			mp_alpha[i] = int_alpha[mp_int[i]]
		end
		-- END convert_to_alpha
		gp_alpha = {[0]=0}
		for i=0,highest_exponent - num_ec_codewords - 1 do
			gp_alpha[i] = 0
		end

		for i=1,num_ec_codewords + 1 do
			gp_alpha[highest_exponent - num_ec_codewords + i - 1] = generator_polynomial[num_ec_codewords][i]
		end

		-- Multiply generator polynomial by first coefficient of the above polynomial

		-- take the highest exponent from the message polynom (alpha) and add
		-- it to the generator polynom
		local exp = mp_alpha[highest_exponent]
		for i=highest_exponent,highest_exponent - num_ec_codewords,-1 do
			if exp ~= 256 then
				if gp_alpha[i] + exp >= 255 then
					gp_alpha[i] = (gp_alpha[i] + exp) % 255
				else
					gp_alpha[i] = gp_alpha[i] + exp
				end
			else
				gp_alpha[i] = 256
			end
		end
		for i=highest_exponent - num_ec_codewords - 1,0,-1 do
			gp_alpha[i] = 256
		end

		
		-- gp_int = convert_to_int(gp_alpha)
		-- mp_int = convert_to_int(mp_alpha)
		gp_int = {}
		mp_int = {}
		for i=0,#gp_alpha do
			gp_int[i] = alpha_int[gp_alpha[i]]
			mp_int[i] = alpha_int[mp_alpha[i]]
		end


		tmp = {}
		for i=highest_exponent,0,-1 do
            tmp[i] = bit32.bxor(gp_int[i],mp_int[i])
		end
		-- remove leading 0's
		he = highest_exponent
		for i=he,0,-1 do
			-- We need to stop if the length of the codeword is matched
			if i < num_ec_codewords then break end
			if tmp[i] == 0 then
				tmp[i] = nil
				highest_exponent = highest_exponent - 1
			else
				break
			end
		end
		mp_int = tmp
	end
	local ret = {}

	-- reverse data
	for i=#mp_int,0,-1 do
		ret[#ret + 1] = mp_int[i]
	end
	return ret
end

--- #### Arranging the data
--- Now we arrange the data into smaller chunks. This table is taken from the spec.
-- ecblocks has 40 entries, one for each version.  Each entry has two or four fields, the odd files are the number of repetitions for the
-- folowing block info. The first entry of the block is the total number of codewords in the block,
-- the second entry is the number of data codewords. The third is not important.
local ecblocks = {
  {  1,{ 26, 19, 2}                 },  -- 7
  {  1,{ 44, 34, 4}                 },  -- 10
  {  1,{ 70, 55, 7}                 },  -- 15
  {  1,{100, 80,10}                 },  -- 20
  {  1,{134,108,13}                 },  -- 26
  {  2,{ 86, 68, 9}                 },  -- 18
  {  2,{ 98, 78,10}                 },  -- 20
  {  2,{121, 97,12}                 },  -- 24
  {  2,{146,116,15}                 },  -- 30
  {  2,{ 86, 68, 9},  2,{ 87, 69, 9}},  -- 18
  {  4,{101, 81,10}                 },  -- 20
}

-- The bits that must be 0 if the version does fill the complete matrix.
-- Example: for version 1, no bits need to be added after arranging the data, for version 2 we need to add 7 bits at the end.
local remainder = {0, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0}

-- This is the formula for table 1 in the spec:
-- function get_capacity_remainder( version )
-- 	local len = version * 4 + 17
-- 	local size = len^2
-- 	local function_pattern_modules = 192 + 2 * len - 32 -- Position Adjustment pattern + timing pattern
-- 	local count_alignemnt_pattern = #alignment_pattern[version]
-- 	if count_alignemnt_pattern > 0 then
-- 		-- add 25 for each aligment pattern
-- 		function_pattern_modules = function_pattern_modules + 25 * ( count_alignemnt_pattern^2 - 3 )
-- 		-- but substract the timing pattern occupied by the aligment pattern on the top and left
-- 		function_pattern_modules = function_pattern_modules - ( count_alignemnt_pattern - 2) * 10
-- 	end
-- 	size = size - function_pattern_modules
-- 	if version > 6 then
-- 		size = size - 67
-- 	else
-- 		size = size - 31
-- 	end
-- 	return math.floor(size/8),math.fmod(size,8)
-- end


--- Example: Version 5-H has four data and four error correction blocks. The table above lists
--- `2, {33,11,11},  2,{34,12,11}` for entry [5][4]. This means we take two blocks with 11 codewords
--- and two blocks with 12 codewords, and two blocks with 33 - 11 = 22 ec codes and another
--- two blocks with 34 - 12 = 22 ec codes.
---	     Block 1: D1  D2  D3  ... D11
---	     Block 2: D12 D13 D14 ... D22
---	     Block 3: D23 D24 D25 ... D33 D34
---	     Block 4: D35 D36 D37 ... D45 D46
--- Then we place the data like this in the matrix: D1, D12, D23, D35, D2, D13, D24, D36 ... D45, D34, D46.  The same goes
--- with error correction codes.

-- The given data can be a string of 0's and 1' (with #string mod 8 == 0).
-- Alternatively the data can be a table of codewords. The number of codewords
-- must match the capacity of the qr code.
local function arrange_codewords_and_calculate_ec( version,data )
	-- If the size of the data is not enough for the codeword, we add 0's and two special bytes until finished.
	local blocks = ecblocks[version]
	local size_datablock_bytes, size_ecblock_bytes
	local datablocks = {}
	local final_ecblocks = {}
	local count = 1
	local pos = 0
	local cpty_ec_bits = 0
	for i=1,#blocks/2 do
		for _=1,blocks[2*i - 1] do
			size_datablock_bytes = blocks[2*i][2]
			size_ecblock_bytes   = blocks[2*i][1] - blocks[2*i][2]
			cpty_ec_bits = cpty_ec_bits + size_ecblock_bytes * 8
			datablocks[#datablocks + 1] = string.sub(data, pos * 8 + 1,( pos + size_datablock_bytes)*8)
			local tmp_tab = calculate_error_correction(datablocks[#datablocks],size_ecblock_bytes)
			local tmp_str = ""
			for x=1,#tmp_tab do
				tmp_str = tmp_str .. binary(tmp_tab[x],8)
			end
			final_ecblocks[#final_ecblocks + 1] = tmp_str
			pos = pos + size_datablock_bytes
			count = count + 1
		end
	end
	local arranged_data = ""
	pos = 1
	repeat
		for i=1,#datablocks do
			if pos < #datablocks[i] then
				arranged_data = arranged_data .. string.sub(datablocks[i],pos, pos + 7)
			end
		end
		pos = pos + 8
	until #arranged_data == #data
	-- ec
	local arranged_ec = ""
	pos = 1
	repeat
		for i=1,#final_ecblocks do
			if pos < #final_ecblocks[i] then
				arranged_ec = arranged_ec .. string.sub(final_ecblocks[i],pos, pos + 7)
			end
		end
		pos = pos + 8
	until #arranged_ec == cpty_ec_bits
	return arranged_data .. arranged_ec
end

--- Step 4: Generate 8 matrices with different masks and calculate the penalty
--- ==========================================================================
---
--- Prepare matrix
--- --------------
--- The first step is to prepare an _empty_ matrix for a given size/mask. The matrix has a
--- few predefined areas that must be black or blank. We encode the matrix with a two
--- dimensional field where the numbers determine which pixel is blank or not.
---
--- The following code is used for our matrix:
---	     0  = not in use yet,
---	    -2  = blank by mandatory pattern,
---	     2  = black by mandatory pattern,
---	    -1  = blank by data,
---	     1  = black by data
---
--- To prepare the _empty_, we add positioning, alingment and timing patters.

--- ### Positioning patterns ###

--- ### Timing patterns ###


--- ### Alignment patterns ###
--- The alignment patterns must be added to the matrix for versions > 1. The amount and positions depend on the versions and are
--- given by the spec. Beware: the patterns must not be placed where we have the positioning patterns
--- (that is: top left, top right and bottom left.)

-- For each version, where should we place the alignment patterns? See table E.1 of the spec
local alignment_pattern = {
  {},{6,18},{6,22},{6,26},{6,30},{6,34}, -- 1-6
  {6,22,38},{6,24,42},{6,26,46},{6,28,50},{6,30,54}, -- 7-11

}



--- ### Type information ###
--- Let's not forget the type information that is in column 9 next to the left positioning patterns and on row 9 below
--- the top positioning patterns. This type information is not fixed, it depends on the mask and the error correction.


local typeinfo = {
	[-1]= "111111111111111", [0] = "111011111000100", "111001011110011", "111110110101010", "111100010011101", "110011000101111", "110001100011000", "110110001000001", "110100101110110"
}



-- Bits for version information 7-40
-- The reversed strings from https://www.thonky.com/qr-code-tutorial/format-version-tables
local version_information = {"001010010011111000", "001111011010000100", "100110010101100100", "110010110010010100",
  "011011111101110100" }


--- Now it's time to use the methods above to create a prefilled matrix
--- that is mask independent.
local function prepare_matrix_without_mask( version )
	local size
	local tab_x = {}

	size = version * 4 + 17
	for i=1,size do
		tab_x[i]={}
		for j=1,size do
			tab_x[i][j] = 0
		end
	end
	-- START add_position_detection_patterns 
	-- allocate quite zone in the matrix area
	for i=1,8 do
		for j=1,8 do
			tab_x[i][j] = -2
			tab_x[size - 8 + i][j] = -2
			tab_x[i][size - 8 + j] = -2
		end
	end
	-- draw the detection pattern (outer)
	for i=1,7 do
		-- top left
		tab_x[1][i]=2
		tab_x[7][i]=2
		tab_x[i][1]=2
		tab_x[i][7]=2

		-- top right
		tab_x[size][i]=2
		tab_x[size - 6][i]=2
		tab_x[size - i + 1][1]=2
		tab_x[size - i + 1][7]=2

		-- bottom left
		tab_x[1][size - i + 1]=2
		tab_x[7][size - i + 1]=2
		tab_x[i][size - 6]=2
		tab_x[i][size]=2
	end
	-- draw the detection pattern (inner)
	for i=1,3 do
		for j=1,3 do
			-- top left
			tab_x[2+j][i+2]=2
			-- top right
			tab_x[size - j - 1][i+2]=2
			-- bottom left
			tab_x[2 + j][size - i - 1]=2
		end
	end
	-- END add_position_detection_patterns 
	-- START add_timing_pattern
	-- The timing patterns (two) are the dashed lines between two adjacent positioning patterns on row/column 7.
	local line,col
	line = 7
	col = 9
	for i=col,#tab_x - 8 do
		tab_x[i][line] = (i % 2 == 1) and 2 or -2
		tab_x[line][i] = (i % 2 == 1) and 2 or -2
	end
	-- END add_timing_pattern


	-- START add_version_information
	if version >= 7 then
		
		local bitstring = version_information[version - 6]
		local x,y, bit
		local start_x, start_y
		-- first top right
		start_x = size - 10
		start_y = 1
		for i=1,#bitstring do
			bit = string.sub(bitstring,i,i)
			x = start_x + (i - 1) % 3
			y = start_y + math.floor( (i - 1) / 3 )
			tab_x[x][y] = (bit == "1") and 2 or -2
		end

		-- now bottom left
		start_x = 1
		start_y = size - 10
		for i=1,#bitstring do
			bit = string.sub(bitstring,i,i)
			x = start_x + math.floor( (i - 1) / 3 )
			y = start_y + (i - 1) % 3
			tab_x[x][y] = (bit == "1") and 2 or -2
		end
	end
	-- END add_version_information

	-- black pixel above lower left position detection pattern
	tab_x[9][size - 7] = 2

	-- START add_alignment_pattern

	--- The alignment pattern has size 5x5 and looks like this:
	---     XXXXX
	---     X   X
	---     X X X
	---     X   X
	---     XXXXX
	local ap = alignment_pattern[(#tab_x - 17) / 4]
	local pos_x, pos_y
	for x=1,#ap do
		for y=1,#ap do
			-- we must not put an alignment pattern on top of the positioning pattern
			if not (x == 1 and y == 1 or x == #ap and y == 1 or x == 1 and y == #ap ) then
				pos_x = ap[x] + 1
				pos_y = ap[y] + 1
				tab_x[pos_x][pos_y] = 2
				tab_x[pos_x+1][pos_y] = -2
				tab_x[pos_x-1][pos_y] = -2
				tab_x[pos_x+2][pos_y] =  2
				tab_x[pos_x-2][pos_y] =  2
				tab_x[pos_x  ][pos_y - 2] = 2
				tab_x[pos_x+1][pos_y - 2] = 2
				tab_x[pos_x-1][pos_y - 2] = 2
				tab_x[pos_x+2][pos_y - 2] = 2
				tab_x[pos_x-2][pos_y - 2] = 2
				tab_x[pos_x  ][pos_y + 2] = 2
				tab_x[pos_x+1][pos_y + 2] = 2
				tab_x[pos_x-1][pos_y + 2] = 2
				tab_x[pos_x+2][pos_y + 2] = 2
				tab_x[pos_x-2][pos_y + 2] = 2

				tab_x[pos_x  ][pos_y - 1] = -2
				tab_x[pos_x+1][pos_y - 1] = -2
				tab_x[pos_x-1][pos_y - 1] = -2
				tab_x[pos_x+2][pos_y - 1] =  2
				tab_x[pos_x-2][pos_y - 1] =  2
				tab_x[pos_x  ][pos_y + 1] = -2
				tab_x[pos_x+1][pos_y + 1] = -2
				tab_x[pos_x-1][pos_y + 1] = -2
				tab_x[pos_x+2][pos_y + 1] =  2
				tab_x[pos_x-2][pos_y + 1] =  2
			end
		end
	end
	-- END add_alignment_pattern
	
	return tab_x
end

--- Finally we come to the place where we need to put the calculated data (remember step 3?) into the qr code.
--- We do this for each mask. BTW speaking of mask, this is what we find in the spec:
---	     Mask Pattern Reference   Condition
---	     000                      (y + x) mod 2 = 0
---	     001                      y mod 2 = 0
---	     010                      x mod 3 = 0
---	     011                      (y + x) mod 3 = 0
---	     100                      ((y div 2) + (x div 3)) mod 2 = 0
---	     101                      (y x) mod 2 + (y x) mod 3 = 0
---	     110                      ((y x) mod 2 + (y x) mod 3) mod 2 = 0
---	     111                      ((y x) mod 3 + (y+x) mod 2) mod 2 = 0


-- Add the data string (0's and 1's) to the matrix for the given mask.
-- Also add typeinfo based on the mask
local function add_data_to_matrix(matrix,data,mask)
	local size = #matrix
	local x,y,positions
	local _x,_y,m
	local dir = 1
	local byte_number = 0

	-- BEGIN add_typeinfo_to_matrix
	local ec_mask_type = typeinfo[mask]

	local bit
	-- vertical from bottom to top
	for i=1,7 do
		bit = string.sub(ec_mask_type,i,i)
		matrix[9][#matrix - i + 1] = ((bit == "1") and 30 or -30) + matrix[9][#matrix - i + 1]
	end
	for i=8,9 do
		bit = string.sub(ec_mask_type,i,i)
		
		matrix[9][17-i] = ((bit == "1") and 30 or -30) + matrix[9][17-i]
	end
	for i=10,15 do
		bit = string.sub(ec_mask_type,i,i)
		
		matrix[9][16-i] = ((bit == "1") and 30 or -30) + matrix[9][16-i]
	end
	-- horizontal, left to right
	for i=1,6 do
		bit = string.sub(ec_mask_type,i,i)
	
		matrix[i][9] = ((bit == "1") and 30 or -30) + matrix[i][9]
	end
	bit = string.sub(ec_mask_type,7,7)

	matrix[8][9] = ((bit == "1") and 30 or -30) + matrix[8][9]
	for i=8,15 do
		bit = string.sub(ec_mask_type,i,i)
		
		matrix[#matrix - 15 + i][9] = ((bit == "1") and 30 or -30) + matrix[#matrix - 15 + i][9]
	end
	-- end

	x,y = size,size

    for byte_idx=1,#data,8 do
        byte_end_idx = math.min(byte_idx+7,#data)
        local byte = string.sub(data,byte_idx,byte_end_idx)
        byte_number = byte_number + 1
		-- BEGIN get_next_free_positions
		-- We need up to 8 positions in the matrix. Only the last few bits may be less then 8.
		-- We generate table of (up to) 8 entries with subtables where
		-- the x coordinate is the first and the y coordinate is the second entry.
        local positions = {}
		local count = 1
		-- 0 = right
		-- 1 = left
		-- 2 = up
		-- 3 = down
		local mode = 0
		while count <= #byte do
			if mode == 0 and matrix[x][y] == 0 then
				positions[#positions + 1] = {x,y}
				mode = 1
				count = count + 1
			elseif mode == 1 and matrix[x-1][y] == 0 then
				positions[#positions + 1] = {x-1,y}
				mode = 0
				count = count + 1
				-- if dir == 1 then
				-- 	y = y - 1
				-- else
				-- 	y = y + 1
				-- end
				y = y + (dir == 1 and -1 or 1)
			elseif mode == 0 and matrix[x-1][y] == 0 then
				positions[#positions + 1] = {x-1,y}
				count = count + 1
				-- if dir == 1 then
				-- 	y = y - 1
				-- else
				-- 	y = y + 1
				-- end
				y = y + (dir == 1 and -1 or 1)
			else
				-- if dir == 1 then
				-- 	y = y - 1
				-- else
				-- 	y = y + 1
				-- end
				y = y + (dir == 1 and -1 or 1)
			end
			if y < 1 or y > #matrix then
				x = x - 2
				-- don't overwrite the timing pattern
				if x == 7 then x = 6 end
				if dir == 1 then
					dir = 3
					y = 1
				else
					dir = 1
					y = #matrix
				end
			end
		end
		-- END get_next_free_positions
        for i=1,#byte do
            _x = positions[i][1]
            _y = positions[i][2]
            -- matrix[_x][_y] = get_pixel_with_mask(mask,_x,_y,string.sub(byte,i,i))
			local x0 = _x - 1
			local y0 = _y - 1

			if mask == 0 and (x0 + y0) % 2 == 0 or
				mask == 1 and y0 % 2 == 0 or
				mask == 2 and x0 % 3 == 0 or
				mask == 3 and (x0 + y0) % 3 == 0 or
				mask == 4 and (math.floor(y0 / 2) + math.floor(x0 / 3)) % 2 == 0 or
				mask == 5 and (x0 * y0) % 2 + (x0 * y0) % 3 == 0 or
				mask == 6 and ((x0 * y0) % 2 + (x0 * y0) % 3) % 2 == 0 or
				mask == 7 and ((x0 * y0) % 3 + (x0 + y0) % 2) % 2 == 0 then
				-- invert the bit,, but store the previous value so we can roll back
				matrix[_x][_y] = 30 - 60 * tonumber(string.sub(byte,i,i)) + matrix[_x][_y]  
			else
				matrix[_x][_y] = -30 + 60 * tonumber(string.sub(byte,i,i)) + matrix[_x][_y] -- don't invert the bit
			end
           
        end
    end
end


--- The total penalty of the matrix is the sum of four steps. The following steps are taken into account:
---
--- 1. Adjacent modules in row/column in same color
--- 1. Block of modules in same color
--- 1. 1:1:3:1:1 ratio (dark:light:dark:light:dark) pattern in row/column
--- 1. Proportion of dark modules in entire symbol
---
--- This all is done to avoid bad patterns in the code that prevent the scanner from
--- reading the code.
-- Return the penalty for the given matrix
local function calculate_penalty(matrix)
	local penalty1, penalty2, penalty3 = 0,0,0
	local size = #matrix
	-- this is for penalty 4
	local number_of_dark_cells = 0

	-- 1: Adjacent modules in row/column in same color
	-- --------------------------------------------
	-- No. of modules = (5+i)  -> 3 + i
	local last_bit_blank -- < 0:  blank, > 0: black
	local is_blank
	local number_of_consecutive_bits
	-- first: vertical
	for x=1,size do
		number_of_consecutive_bits = 0
		last_bit_blank = nil
		for y = 1,size do
			if matrix[x][y] > 0 then
				-- small optimization: this is for penalty 4
				number_of_dark_cells = number_of_dark_cells + 1
				is_blank = false
			else
				is_blank = true
			end
			if last_bit_blank == is_blank then
				number_of_consecutive_bits = number_of_consecutive_bits + 1
			else
				if number_of_consecutive_bits >= 5 then
					penalty1 = penalty1 + number_of_consecutive_bits - 2
				end
				number_of_consecutive_bits = 1
			end
			last_bit_blank = is_blank
		end
		if number_of_consecutive_bits >= 5 then
			penalty1 = penalty1 + number_of_consecutive_bits - 2
		end
	end
	-- now horizontal
	for y=1,size do
		number_of_consecutive_bits = 0
		last_bit_blank = nil
		for x = 1,size do
			is_blank = matrix[x][y] < 0
			if last_bit_blank == is_blank then
				number_of_consecutive_bits = number_of_consecutive_bits + 1
			else
				if number_of_consecutive_bits >= 5 then
					penalty1 = penalty1 + number_of_consecutive_bits - 2
				end
				number_of_consecutive_bits = 1
			end
			last_bit_blank = is_blank
		end
		if number_of_consecutive_bits >= 5 then
			penalty1 = penalty1 + number_of_consecutive_bits - 2
		end
	end
	for x=1,size do
		for y=1,size do
			-- 2: Block of modules in same color
			-- -----------------------------------
			-- Blocksize = m × n  -> 3 × (m-1) × (n-1)
			if (y < size - 1) and ( x < size - 1) and ( (matrix[x][y] < 0 and matrix[x+1][y] < 0 and matrix[x][y+1] < 0 and matrix[x+1][y+1] < 0) or (matrix[x][y] > 0 and matrix[x+1][y] > 0 and matrix[x][y+1] > 0 and matrix[x+1][y+1] > 0) ) then
				penalty2 = penalty2 + 3
			end

			-- 3: 1:1:3:1:1 ratio (dark:light:dark:light:dark) pattern in row/column
			-- ------------------------------------------------------------------
			-- Gives 40 points each
			--
			-- I have no idea why we need the extra 0000 on left or right side. The spec doesn't mention it,
			-- other sources do mention it. This is heavily inspired by zxing.
			if (y + 6 < size and
				matrix[x][y] > 0 and
				matrix[x][y +  1] < 0 and
				matrix[x][y +  2] > 0 and
				matrix[x][y +  3] > 0 and
				matrix[x][y +  4] > 0 and
				matrix[x][y +  5] < 0 and
				matrix[x][y +  6] > 0 and
				((y + 10 < size and
					matrix[x][y +  7] < 0 and
					matrix[x][y +  8] < 0 and
					matrix[x][y +  9] < 0 and
					matrix[x][y + 10] < 0) or
				 (y - 4 >= 1 and
					matrix[x][y -  1] < 0 and
					matrix[x][y -  2] < 0 and
					matrix[x][y -  3] < 0 and
					matrix[x][y -  4] < 0))) then penalty3 = penalty3 + 40 end
			if (x + 6 <= size and
				matrix[x][y] > 0 and
				matrix[x +  1][y] < 0 and
				matrix[x +  2][y] > 0 and
				matrix[x +  3][y] > 0 and
				matrix[x +  4][y] > 0 and
				matrix[x +  5][y] < 0 and
				matrix[x +  6][y] > 0 and
				((x + 10 <= size and
					matrix[x +  7][y] < 0 and
					matrix[x +  8][y] < 0 and
					matrix[x +  9][y] < 0 and
					matrix[x + 10][y] < 0) or
				 (x - 4 >= 1 and
					matrix[x -  1][y] < 0 and
					matrix[x -  2][y] < 0 and
					matrix[x -  3][y] < 0 and
					matrix[x -  4][y] < 0))) then penalty3 = penalty3 + 40 end
		end
	end
	-- 4: Proportion of dark modules in entire symbol
	-- ----------------------------------------------
	-- 50 ± (5 × k)% to 50 ± (5 × (k + 1))% -> 10 × k
	local dark_ratio = number_of_dark_cells / ( size * size )
	local penalty4 = math.floor(math.abs(dark_ratio * 100 - 50)) * 2
	return penalty1 + penalty2 + penalty3 + penalty4
end



-- Return the matrix with the smallest penalty. To to this
-- we try out the matrix for all 8 masks and determine the
-- penalty (score) each.
local function get_matrix_with_lowest_penalty(version,data)
	local tab = prepare_matrix_without_mask(version)
	local min_penalty = 9e99
	local min_mask = 0
	for mask=0,7 do
		add_data_to_matrix(tab,data,mask) -- apply mask
		local penalty = calculate_penalty(tab)
		if penalty < min_penalty then
			min_penalty = penalty
			min_mask = mask
		end
		-- roll back applying the mask
		for x=1,#tab do
			for y=1,#tab do
				if tab[x][y] > 25 then
					tab[x][y] = tab[x][y] - 30
				elseif tab[x][y] < -25 then
					tab[x][y] = tab[x][y] + 30
				end
			end
		end
	end
	-- apply the mask with the lowest penalty
	add_data_to_matrix(tab,data,min_mask)
	return tab
end

--- The main function. We connect everything together. Remember from above:
---
--- 1. Determine version, ec level and mode (=encoding) for codeword
--- 1. Encode data
--- 1. Arrange data and calculate error correction code
--- 1. Generate 8 matrices with different masks and calculate the penalty
--- 1. Return qrcode with least penalty
-- If ec_level or mode is given, use the ones for generating the qrcode. (mode is not implemented yet)
local function qrcode(str) -- luacheck: no unused args


	-- calculate the smallest version for this codeword.
    local version = 40
	for version_i=1,#capacity do
		local digits
		if version_i < 10 then
			digits = 8
		elseif version_i < 27 then
			digits = 10
		end
		-- 4 is the the mode indicator
		if math.floor((capacity[version_i] * 8 - 4 - digits) * 1 / 13) >= #str then
			if version_i <= version then
				version = version_i
			end
			break
		end
	end

	-- encode the data length as a bitstring
    local digits
	if version < 10 then
		digits = 8
	elseif version < 27 then
		digits = 10
	else
		assert(false, "version > 27 not supported")
	end
	local len_bitstring = binary(#str,digits)
    
    -- raw data begins with: mode, bitstring length
    -- the mode here is: 4 (binary)
	local data_raw = "0100" .. len_bitstring
	
    -- Encode string data as binary (in gps coords we have a comma, so we need to use the binary mode instead of alphanumeric)
    for i=1,#str do
        data_raw = data_raw .. binary(string.byte(string.sub(str,i,i)),8)
    end

	-- BEGIN add_pad_data
	-- Encoding the codeword is not enough. We need to make sure that
	-- the length of the binary string is equal to the number of codewords of the version.
	local count_to_pad
	local cpty = capacity[version] * 8

	count_to_pad = math.min(4,cpty - #data_raw)
	if count_to_pad > 0 then
		data_raw = data_raw .. string.rep("0",count_to_pad)
	end
	if #data_raw % 8 ~= 0 then
		data_raw = data_raw .. string.rep("0",8 - #data_raw % 8)
	end
	-- add "11101100" and "00010001" until enough data
	while #data_raw < cpty do
		data_raw = data_raw .. "11101100"
		if #data_raw < cpty then
			data_raw = data_raw .. "00010001"
		end
	end
	-- END add_pad_data

    -- arrange data and calculate error correction
	data_raw = arrange_codewords_and_calculate_ec(version,data_raw)
	if #data_raw % 8 ~= 0 then
		return nil
	end
	data_raw = data_raw .. string.rep("0",remainder[version])
	collectgarbage("collect") -- collect before creating matrix
	local tab = get_matrix_with_lowest_penalty(version,data_raw)
	collectgarbage("collect") -- collect after creating matrix
	return tab
end




local INVERTED = false
local QR_REFRESH_INTERVAL = 15 * 100
local mid = LCD_W / 2


local my_gpsId = nil
local has_gps = false
local last_latitude, last_longitude = 0.0, 0.0
local latitude, longitude = 0.0, 0.0

local needs_qr_data = false
local qr_data = nil
local last_qr_refresh = 0


local function init_func()
    my_gpsId  = getFieldInfo("GPS") and getFieldInfo("GPS").id or nil;
end

local function bg_func()
	if my_gpsId and getValue(my_gpsId) ~= 0 then
		local gps = getValue(my_gpsId)

		latitude = string.format("%.6f", gps.lat)
		longitude = string.format("%.6f", gps.lon)
        has_gps = true
		
	end	

	-- render QR code requested by the UI func
	if needs_qr_data then
		needs_qr_data = false
		
		-- collectgarbage("stop")
		-- start_k, start_b = collectgarbage("count")
		
		qr_data = qrcode("geo:"..last_latitude..","..last_longitude)
		
		-- end_k, end_b = collectgarbage("count")
		-- collectgarbage("restart")
		-- print(string.format("Used mem: %.2f KB", (end_k - start_k)))
	end
end
-- local qrencode = loadScript("/SCRIPTS/TELEMETRY/qrenc.lua")()

local function run_func()
    
	lcd.clear()

    if not my_gpsId then
        lcd.drawText(mid - 40, LCD_H/2-5, "No GPS sensor")
        lcd.drawText(mid - 45, LCD_H/2+5, "Please discover")
        return 0
    end
	if not has_gps then
		lcd.drawText(mid - 40, LCD_H/2-5, "No GPS data yet")
		return 0
	end

	if INVERTED == true then
		lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, INVERS)
    end
	local now = getTime()
	if not qr_data or ((last_latitude ~= latitude or last_longitude ~= longitude) and now - last_qr_refresh >= QR_REFRESH_INTERVAL) then
		-- generate the QR code on demand
		needs_qr_data = true
		last_latitude = latitude
		last_longitude = longitude
		last_qr_refresh = now
		
	end
	
	local qr_width = 64
    if qr_data then
		qr_width = #qr_data * 2 + 4
        for x = 1, #qr_data do
            for y = 1, #qr_data[x] do
                -- print(x, y, data[x][y])
                if qr_data[x][y] > 0 then
					lcd.drawFilledRectangle(x * 2, y * 2, 2, 2)
                end
				
            end
        end
    else
        lcd.drawText(0, 20, "QR...")
    end
    if INVERTED == true then
	    lcd.drawFilledRectangle(qr_width, 0, LCD_W - qr_width, LCD_H, 0)
    end
	qr_width = qr_width + 2
	lcd.drawText(qr_width, 5, "Lat")
	lcd.drawText(qr_width, 15, latitude)
	lcd.drawText(qr_width, 25, "Lon")
	lcd.drawText(qr_width, 35, longitude)
	lcd.drawText(qr_width, 50, string.format("%.0fs ago", ((now - last_qr_refresh) / 100)))    
   
  

	return 0
end

return {run=run_func, init=init_func, background=bg_func}
