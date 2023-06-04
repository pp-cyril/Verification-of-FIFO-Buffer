interface fifo_if;

logic clock, rd, wr;
logic full, empty;
logic [7:0] data_in;
logic [7:0] data_out;
logic rst;
endinterface

////////////////////////////////TRANSACTION////////////////////////////////
//add variables ports of DUT except the globals signals
//modifier for input port
//constraints

class transaction;

rand bit rd, wr;
rand bit [7:0] data_in;
bit full , empty;
bit[7:0] data_out;


constraint wr_rd {
    rd != wr;
    wr dist {0 :/ 50, 1 :/ 50};
    rd dist {0 :/ 50, 1 :/ 50};
}

constraint data_con {
    data_in > 1; 
    data_in < 5;
}

function void display (input string tag); //tag specifies which class is printing value
    $display("[%0s] : WR : %0b\t RD:%0b\t DATAWR : %0d\t DATARD : %0d\t FULL : %0b\t EMPTY : %0b @ %0t", tag, wr, rd, data_in, data_out, full, empty,$time);
endfunction

function transaction copy();
    copy = new();
    copy.rd = this.rd;
    copy.wr = this.wr;
    copy.data_in = this.data_in;
    copy.data_out = this.data_out;
    copy.full = this.full;
    copy.empty = this.empty;
endfunction


endclass


///////////////////////////////GENERATOR///////////////////////////////////
//randomize transaction and send to driver
//sense event from scoreboard and driver --> next transaction
class generator;

transaction trans;
mailbox #(transaction) mbx;

int count = 0;
event next; 
event done;

function new(mailbox #(transaction) mbx);
this.mbx = mbx;
trans = new();
endfunction

task run();

repeat(count) begin
    assert(trans.randomize()) else $display("Randomization failed");
    mbx.put(trans.copy);
    trans.display("GEN");
    @(next); //completion of required number of transactions
end

-> done; //when to send next transaction

endtask
endclass


//////////////////////////////////////DRIVER/////////////////////////////////
//receive from generator
//apply reset to dut and transaction to dut with interface
// notify generator
class driver;

virtual fifo_if fif;
mailbox #(transaction) mbx;

transaction data;
event next;

function new(mailbox #(transaction) mbx);
this.mbx = mbx;
endfunction

task reset();
fif.rst <= 1;
fif.rd <= 0;
fif.wr <= 0;
fif.data_in <= 0;
repeat(5) @(posedge fif.clock);
fif.rst <= 0;
endtask

task run();

forever begin
    mbx.get(data); //get data from generator
    data.display("DRIV");

    fif.rd <= data.rd;
    fif.wr <= data.wr;
    fif.data_in <= data.data_in;
    repeat(2) @(posedge fif.clock);
    ->next;
end
endtask
endclass


//////////////////////////////////////////////MONITOR////////////////////////
//capture DUT response 
//send response to Scoreboard
//also control data to be sent to specific operation (not valid for fifo)

class monitor;

virtual fifo_if fif;
mailbox #(transaction) mbx;

transaction trans;

function new(mailbox #(transaction) mbx);
this.mbx = mbx;
endfunction

task run();
trans = new();
forever begin
    repeat(2) @(posedge fif.clock) begin
        trans.wr = fif.wr;
        trans.rd = fif.rd;
        trans.data_in = fif.data_in;
        trans.data_out = fif.data_out;
        trans.full = fif.full;
        trans.empty = fif.empty;

        mbx.put(trans);
        trans.display("MON");
end
end
endtask

endclass



///////////////////////SCOREBOARD////////////////////////////////////////////
//receive from monitor
//store transaction
//compare the result
class scoreboard;

mailbox #(transaction) mbx;
transaction trans;
event next;

bit [7:0] din[$];
bit [7:0] temp;

function new(mailbox #(transaction) mbx);
this.mbx = mbx;
endfunction

task run();

forever begin
    mbx.get(trans);
    trans.display("SCO");

    if(trans.wr == 1) begin
        din.push_front(trans.data_in);
      $display("[SCO] : DATA STORED IN QUEUE :%0d", trans.data_in);
    end

    if(trans.rd == 1) begin
        if(trans.empty == 0) begin
            temp = din.pop_back();
            if(trans.data_out == temp)
            $display ("DATA MATCH");
            else begin
            $display("[SCO] : FIFO IS EMPTY");
          end
        end
    end
  ->next;
end
endtask

endclass

class environment;

generator gen;
driver drv;
monitor mon;
scoreboard sco;

event nextgs;
mailbox #(transaction) gdmbx;
mailbox #(transaction) msmbx;

virtual fifo_if fif;
function new(virtual fifo_if fif);

gdmbx = new();
gen = new(gdmbx);
drv = new(gdmbx);

msmbx = new();
mon = new(msmbx);
sco = new(msmbx);

this.fif = fif;
drv.fif = this.fif;
mon.fif = this.fif;

gen.next = nextgs;
sco.next = nextgs;

endfunction

task pre_test();

drv.reset();
endtask

task test();

fork
    gen.run();
    drv.run();
    mon.run();
    sco.run();
join_any

endtask

task post_test();
wait(gen.done.triggered);
$finish();
endtask

task run();
pre_test();
test();
post_test();
endtask

endclass

module tb;

fifo_if fif();

fifo dut (fif.clock, fif.rd, fif.wr,fif.full, fif.empty, fif.data_in, fif.data_out, fif.rst);

initial begin
    fif.clock <= 0;
end

always #10 fif.clock <= ~fif.clock;

environment env;

initial begin
    env = new(fif);
    env.gen.count = 20;
    env.run();
end

endmodule