`timescale 1ns / 1ps

module full_adder_tb;

    // Inputs to UUT (driven as reg)
    reg a;
    reg b;
    reg cin;

    // Outputs from UUT (monitored as wire)
    wire sum;
    wire cout;

    // Instantiate your full_adder
    full_adder uut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout)
    );

    initial begin
        // Generate waveform file for GTKWave viewing
        $dumpfile("full_adder.vcd");
        $dumpvars(0, full_adder_tb);

        // Display results whenever any signal changes
        $monitor("Time = %0t | a = %b, b = %b, cin = %b | sum = %b, cout = %b", 
                 $time, a, b, cin, sum, cout);

        // Apply all 8 input combinations with a 10ns delay between each
        a = 0; b = 0; cin = 0; #10;
        a = 0; b = 0; cin = 1; #10;
        a = 0; b = 1; cin = 0; #10;
        a = 0; b = 1; cin = 1; #10;
        a = 1; b = 0; cin = 0; #10;
        a = 1; b = 0; cin = 1; #10;
        a = 1; b = 1; cin = 0; #10;
        a = 1; b = 1; cin = 1; #10;

        $finish;
    end

endmodule