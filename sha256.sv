// ======================================================== ITERATIVE ======================================================== //
// module sha256(
//     input logic clock,
//     input logic reset,
//     input logic start,
//     input logic [511:0] block,
//     output logic [255:0] digest,
//     output logic finish
// );

//     function automatic logic [31:0] rotate_right(input logic[31:0] in, input int positions);
//         return (in >> positions) | (in << (32-positions));
//     endfunction

//     function automatic logic [31:0] s0(input logic[31:0] in);
//         return (rotate_right(in, 7) ^ rotate_right(in,18) ^ (in >> 3));
//     endfunction

//     function automatic logic [31:0] s1(input logic [31:0] in);
//         return (rotate_right(in, 17) ^ rotate_right(in, 19) ^ (in >> 10));
//     endfunction

//     function automatic logic [31:0] choose(input logic [31:0] select, input logic [31:0] x, input logic [31:0] y);
//         return (x & select) ^ (y & ~select);
//     endfunction

//     function automatic logic [31:0] majority (input logic [31:0] j, input logic [31:0] k, input logic [31:0] l);
//         return (j & k) ^ (j & l) ^ (k & l);
//     endfunction

//     function automatic logic [31:0] S0 (input logic [31:0] in);
//         return rotate_right(in, 2) ^ rotate_right(in, 13) ^ rotate_right(in, 22);
//     endfunction

//     function automatic logic [31:0] S1 (input logic [31:0] in);
//         return rotate_right(in, 6) ^ rotate_right(in, 11) ^ rotate_right(in ,25);
//     endfunction

//     (* romstyle = "logic" *) localparam logic [31:0] K [0:63] = '{
//         32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5,
//         32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
//         32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3,
//         32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
//         32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc,
//         32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
//         32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7,
//         32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
//         32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13,
//         32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
//         32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3,
//         32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
//         32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5,
//         32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
//         32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208,
//         32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2
//     };

//     logic [31:0] temp1;
//     logic [31:0] temp2;
//     (* ramstyle = "registers" *) logic [31:0] W [0:63];

//     logic [31:0] a, b, c, d, e, f, g, h;
//     logic [31:0] H0, H1, H2, H3, H4, H5, H6, H7;
//     logic [31:0] w_update;
//     logic [6:0] timer;

//     assign temp1 = (timer < 64) ? (h + S1(e) + choose(e,f,g) + K[timer[5:0]] + w_update) : '0;
//     assign temp2 = (timer < 64) ? (S0(a) + majority(a,b,c)) : '0;

//     always_comb begin
//         if (timer < 16) begin
//             w_update = block[511 - timer * 32 -: 32];
//         end else begin
//             w_update = s1(W[timer-2]) + W[timer-7] + s0(W[timer-15]) + W[timer-16];
//         end
//     end

//     always_ff @(posedge clock or negedge reset) begin
//         if (!reset) begin

//             timer <= 7'd65;
//             finish <= 0;

//             H0 <= 32'h6a09e667;
//             H1 <= 32'hbb67ae85;
//             H2 <= 32'h3c6ef372;
//             H3 <= 32'ha54ff53a;
//             H4 <= 32'h510e527f;
//             H5 <= 32'h9b05688c;
//             H6 <= 32'h1f83d9ab;
//             H7 <= 32'h5be0cd19;

//         end else if (start && timer > 63) begin

//             finish <= 0;
//             timer <= 7'd0;

//             a <= 32'h6a09e667; b <= 32'hbb67ae85; c <= 32'h3c6ef372; d <= 32'ha54ff53a;
//             e <= 32'h510e527f; f <= 32'h9b05688c; g <= 32'h1f83d9ab; h <= 32'h5be0cd19;

//             H0 <= 32'h6a09e667; H1 <= 32'hbb67ae85; H2 <= 32'h3c6ef372; H3 <= 32'ha54ff53a;
//             H4 <= 32'h510e527f; H5 <= 32'h9b05688c; H6 <= 32'h1f83d9ab; H7 <= 32'h5be0cd19;

//         end else if (timer < 64) begin

//             W[timer] <= w_update;

//             h <= g;
//             g <= f;
//             f <= e;
//             e <= d + temp1;
//             d <= c;
//             c <= b;
//             b <= a;
//             a <= temp1 + temp2;

//             timer <= timer + 1;

//         end else if (timer == 64) begin

//             H0 <= H0 + a; H1 <= H1 + b; H2 <= H2 + c; H3 <= H3 + d;
//             H4 <= H4 + e; H5 <= H5 + f; H6 <= H6 + g; H7 <= H7 + h;

//             finish <= 1;
//             timer <= 7'd65;

//         end
//     end

//     assign digest = {H0, H1, H2, H3, H4, H5, H6, H7};

// endmodule


// ======================================================== PIPELINED ======================================================== //
module sha256 (
    input  logic         clock,
    input  logic         reset,
    input  logic         start,
    input  logic [511:0] block,
    output logic [255:0] digest,
    output logic         finish
);

    function automatic logic [31:0] rotate_right(input logic [31:0] in, input int positions);
        return (in >> positions) | (in << (32 - positions));
    endfunction

    function automatic logic [31:0] s0(input logic [31:0] in);
        return (rotate_right(in, 7) ^ rotate_right(in, 18) ^ (in >> 3));
    endfunction

    function automatic logic [31:0] s1(input logic [31:0] in);
        return (rotate_right(in, 17) ^ rotate_right(in, 19) ^ (in >> 10));
    endfunction

    function automatic logic [31:0] choose(input logic [31:0] select, input logic [31:0] x, input logic [31:0] y);
        return (x & select) ^ (y & ~select);
    endfunction

    function automatic logic [31:0] majority(input logic [31:0] j, input logic [31:0] k, input logic [31:0] l);
        return (j & k) ^ (j & l) ^ (k & l);
    endfunction

    function automatic logic [31:0] S0(input logic [31:0] in);
        return rotate_right(in, 2) ^ rotate_right(in, 13) ^ rotate_right(in, 22);
    endfunction

    function automatic logic [31:0] S1(input logic [31:0] in);
        return rotate_right(in, 6) ^ rotate_right(in, 11) ^ rotate_right(in, 25);
    endfunction


    // localparam logic [31:0] K [0:63] = '{
    //     32'h428a2f98, 32'h71374491, 32'hb5c0fbcf, 32'he9b5dba5,
    //     32'h3956c25b, 32'h59f111f1, 32'h923f82a4, 32'hab1c5ed5,
    //     32'hd807aa98, 32'h12835b01, 32'h243185be, 32'h550c7dc3,
    //     32'h72be5d74, 32'h80deb1fe, 32'h9bdc06a7, 32'hc19bf174,
    //     32'he49b69c1, 32'hefbe4786, 32'h0fc19dc6, 32'h240ca1cc,
    //     32'h2de92c6f, 32'h4a7484aa, 32'h5cb0a9dc, 32'h76f988da,
    //     32'h983e5152, 32'ha831c66d, 32'hb00327c8, 32'hbf597fc7,
    //     32'hc6e00bf3, 32'hd5a79147, 32'h06ca6351, 32'h14292967,
    //     32'h27b70a85, 32'h2e1b2138, 32'h4d2c6dfc, 32'h53380d13,
    //     32'h650a7354, 32'h766a0abb, 32'h81c2c92e, 32'h92722c85,
    //     32'ha2bfe8a1, 32'ha81a664b, 32'hc24b8b70, 32'hc76c51a3,
    //     32'hd192e819, 32'hd6990624, 32'hf40e3585, 32'h106aa070,
    //     32'h19a4c116, 32'h1e376c08, 32'h2748774c, 32'h34b0bcb5,
    //     32'h391c0cb3, 32'h4ed8aa4a, 32'h5b9cca4f, 32'h682e6ff3,
    //     32'h748f82ee, 32'h78a5636f, 32'h84c87814, 32'h8cc70208,
    //     32'h90befffa, 32'ha4506ceb, 32'hbef9a3f7, 32'hc67178f2
    // };

    // iverilog compatibility
    logic [31:0] K [0:63];

    initial begin
        K[0]  = 32'h428a2f98; K[1]  = 32'h71374491; K[2]  = 32'hb5c0fbcf; K[3]  = 32'he9b5dba5;
        K[4]  = 32'h3956c25b; K[5]  = 32'h59f111f1; K[6]  = 32'h923f82a4; K[7]  = 32'hab1c5ed5;
        K[8]  = 32'hd807aa98; K[9]  = 32'h12835b01; K[10] = 32'h243185be; K[11] = 32'h550c7dc3;
        K[12] = 32'h72be5d74; K[13] = 32'h80deb1fe; K[14] = 32'h9bdc06a7; K[15] = 32'hc19bf174;
        K[16] = 32'he49b69c1; K[17] = 32'hefbe4786; K[18] = 32'h0fc19dc6; K[19] = 32'h240ca1cc;
        K[20] = 32'h2de92c6f; K[21] = 32'h4a7484aa; K[22] = 32'h5cb0a9dc; K[23] = 32'h76f988da;
        K[24] = 32'h983e5152; K[25] = 32'ha831c66d; K[26] = 32'hb00327c8; K[27] = 32'hbf597fc7;
        K[28] = 32'hc6e00bf3; K[29] = 32'hd5a79147; K[30] = 32'h06ca6351; K[31] = 32'h14292967;
        K[32] = 32'h27b70a85; K[33] = 32'h2e1b2138; K[34] = 32'h4d2c6dfc; K[35] = 32'h53380d13;
        K[36] = 32'h650a7354; K[37] = 32'h766a0abb; K[38] = 32'h81c2c92e; K[39] = 32'h92722c85;
        K[40] = 32'ha2bfe8a1; K[41] = 32'ha81a664b; K[42] = 32'hc24b8b70; K[43] = 32'hc76c51a3;
        K[44] = 32'hd192e819; K[45] = 32'hd6990624; K[46] = 32'hf40e3585; K[47] = 32'h106aa070;
        K[48] = 32'h19a4c116; K[49] = 32'h1e376c08; K[50] = 32'h2748774c; K[51] = 32'h34b0bcb5;
        K[52] = 32'h391c0cb3; K[53] = 32'h4ed8aa4a; K[54] = 32'h5b9cca4f; K[55] = 32'h682e6ff3;
        K[56] = 32'h748f82ee; K[57] = 32'h78a5636f; K[58] = 32'h84c87814; K[59] = 32'h8cc70208;
        K[60] = 32'h90befffa; K[61] = 32'ha4506ceb; K[62] = 32'hbef9a3f7; K[63] = 32'hc67178f2;
    end

    logic [31:0] a_val_reg [1:64];
    logic [31:0] b_val_reg [1:64];
    logic [31:0] c_val_reg [1:64];
    logic [31:0] d_val_reg [1:64];
    logic [31:0] e_val_reg [1:64];
    logic [31:0] f_val_reg [1:64];
    logic [31:0] g_val_reg [1:64];
    logic [31:0] h_val_reg [1:64];
    
    logic [31:0] w_val_reg [1:64][0:15]; 
    logic        v_val_reg [1:64];

    genvar i;
    genvar j;
    generate
        for (i = 0; i < 64; i++) begin : pipe_stage
            
            logic [31:0] a_in, b_in, c_in, d_in, e_in, f_in, g_in, h_in;
            logic [31:0] w_in [0:15];
            logic        v_in;

            if (i == 0) begin
                assign a_in = 32'h6a09e667;
                assign b_in = 32'hbb67ae85;
                assign c_in = 32'h3c6ef372;
                assign d_in = 32'ha54ff53a;
                assign e_in = 32'h510e527f;
                assign f_in = 32'h9b05688c;
                assign g_in = 32'h1f83d9ab;
                assign h_in = 32'h5be0cd19;
                assign v_in = start;
                
                for (j = 0; j < 16; j++) begin : w_init
                    assign w_in[j] = block[511 - (j * 32) -: 32];
                end
            end else begin
                assign a_in = a_val_reg[i];
                assign b_in = b_val_reg[i];
                assign c_in = c_val_reg[i];
                assign d_in = d_val_reg[i];
                assign e_in = e_val_reg[i];
                assign f_in = f_val_reg[i];
                assign g_in = g_val_reg[i];
                assign h_in = h_val_reg[i];
                assign v_in = v_val_reg[i];
                
                for (j = 0; j < 16; j++) begin : w_pass
                    assign w_in[j] = w_val_reg[i][j];
                end
            end

            logic [31:0] current_w;
            if (i < 16) begin
                assign current_w = w_in[0];
            end else begin
                assign current_w = s1(w_in[14]) + w_in[9] + s0(w_in[1]) + w_in[0];
            end

            logic [31:0] temp1, temp2;
            assign temp1 = h_in + S1(e_in) + choose(e_in, f_in, g_in) + K[i] + current_w;
            assign temp2 = S0(a_in) + majority(a_in, b_in, c_in);

            always_ff @(posedge clock or negedge reset) begin
                if (!reset) begin
                    v_val_reg[i+1] <= 1'b0;
                    a_val_reg[i+1] <= '0; b_val_reg[i+1] <= '0; c_val_reg[i+1] <= '0; d_val_reg[i+1] <= '0;
                    e_val_reg[i+1] <= '0; f_val_reg[i+1] <= '0; g_val_reg[i+1] <= '0; h_val_reg[i+1] <= '0;
                    for (int k = 0; k < 16; k++) w_val_reg[i+1][k] <= '0;
                end else begin
                    v_val_reg[i+1] <= v_in;
                    if (v_in) begin
                        h_val_reg[i+1] <= g_in;
                        g_val_reg[i+1] <= f_in;
                        f_val_reg[i+1] <= e_in;
                        e_val_reg[i+1] <= d_in + temp1;
                        d_val_reg[i+1] <= c_in;
                        c_val_reg[i+1] <= b_in;
                        b_val_reg[i+1] <= a_in;
                        a_val_reg[i+1] <= temp1 + temp2;

                        for (int k = 0; k < 15; k++) begin
                            w_val_reg[i+1][k] <= w_in[k+1];
                        end
                        w_val_reg[i+1][15] <= current_w;
                    end
                end
            end
            
        end
    endgenerate

    assign finish = v_val_reg[64];
    
    assign digest = {
        32'h6a09e667 + a_val_reg[64],
        32'hbb67ae85 + b_val_reg[64],
        32'h3c6ef372 + c_val_reg[64],
        32'ha54ff53a + d_val_reg[64],
        32'h510e527f + e_val_reg[64],
        32'h9b05688c + f_val_reg[64],
        32'h1f83d9ab + g_val_reg[64],
        32'h5be0cd19 + h_val_reg[64]
    };

endmodule