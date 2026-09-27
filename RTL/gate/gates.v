`timescale 1ns/1ps

module and_gate(a,b,y);
    input wire a,b;
    output wire y;
    assign y = a&b;
endmodule  

module or_gate(a,b,y);
    input wire a,b;
    output wire y;
    assign y = a|b;
endmodule    

module xor_gate(a,b,y);
    input wire a,b;
    output wire y;
    assign y = a^b;
endmodule


module not_gate(a,y);
    input wire a;
    output wire y;
    assign y = ~a;
endmodule 


module nand_gate(a,b,y);
    input wire a,b;
    output wire y;
    assign y = ~(a&b);
endmodule 


module nor_gate(a,b,y);
    input wire a,b;
    output wire y;
    assign y = ~(a|b);
endmodule 
