`include "defines.v"

//五级流水线基本框架

module pc_reg (
    input wire clk,
    input wire rst,
    output reg[`InstAddrBus] pc,        //要读取的指令地址
    output reg ce                       //指令存储器的使能信号
);
    always @(posedge clk) 
    begin
        if(rst == `RstEnable)begin      //先判断是否复位决定指令存储器是否开启
            ce <= `ChipDisable;         //复位时指令存储器禁用
        end else begin
            ce <= `ChipEnable;
        end
    end

    always @(posedge clk) begin
        if(ce == `ChipDisable) begin
            pc <= 32'h00000000;         //复位
        end else begin
            pc <= pc + 4'h4;            //一条指令4个字节
        end     
    end

endmodule


module if_id (
    input wire clk,
    input wire rst,

    //取值阶段的信号，指令宽度为32
    input wire[`InstAddrBus] if_pc,     //取值阶段对应指令地址
    input wire[`InstBus] if_inst,       //取出的指令

    //译码阶段的信号
    output reg[`InstAddrBus] id_pc,     //译码阶段对应的指令地址
    output reg[`InstBus] id_inst        //译码阶段的指令
);
    always @(posedge clk) begin
        if(rst == `RstEnable) begin
            id_pc <= `ZeroWord;         //复位pc为0，指令为0（空指令）
            id_inst <= `ZeroWord;
        end else begin
            id_pc <= if_pc;             //其余阶段向下传递取值阶段的值
            id_inst <= if_inst;
        end
    end
endmodule


//32个32位通用整数寄存器，可同时进行两个寄存器的读操作和一个寄存器的写操作
module regfile (
    input wire clk,
    input wire rst,

    //写端口
    input wire we,
    input wire [`RegAddrBus] waddr,     //写入的寄存器地址
    input wire [`RegBus] wdata,         //写入的数据

    //读端口1
    input wire re1,
    input wire [`RegAddrBus] raddr1,    //第一个读寄存器端口要读出的寄存器地址
    output reg [`RegBus] rdata1,        //读出的寄存器值

    //读端口2
    input wire re2,
    input wire [`RegAddrBus] raddr2,
    output reg [`RegBus] rdata2
);
    

//定义32个32位寄存器（reg位寄存器类型，regs为数组名），对应cpu通用寄存器集合
reg[`RegBus] regs[0:`RegNum-1];         //每个数组元素是一个RegBus位宽的寄存器

always @(posedge clk or posedge rst) begin : inst_block         //给模块命名
    integer i;                      //只能在有名字的模块内部begin之前、always开头声明，或在模块外部声明
    if (rst == `RstEnable) begin
        for (i = 0; i< `RegNum; i = i+1) begin
            regs[i] <= `ZeroWord;
        end
    end else if((we == `WriteEnable)&&(waddr != `RegNumLog2'h0)) begin
        regs[waddr] <= wdata;       //把写的数据写入要写入地址的寄存器中
    end
end
//判断写地址不能为0是因为：在mips中规定有一个特殊的$0(零寄存器)，只能为0且不能修改


always @(*) begin
    if(rst == `RstEnable) begin
        rdata1 <= `ZeroWord;
    end else if(raddr1 == `RegNumLog2'h0) begin
        rdata1 <= `ZeroWord;
    end else if((raddr1 == waddr)&&(we == `WriteEnable)&&(re1 == `ReadEnable)) begin
        rdata1 <= wdata;
        //第一个读取寄存器端口要读取的寄存器和要写入的目的寄存器相同，直接将要写入的值作为读寄存器端口输出
    end else if(re1 == `ReadEnable) begin
        rdata1 <= regs[raddr1];
        //给出要读取的目标寄存器地址对应寄存器的值
    end else begin
        rdata1 <= `ZeroWord;
        //第一个读寄存器端口不能使用时，输出0
    end
end


always @(*) begin
    if(rst == `RstEnable) begin
        rdata2 <= `ZeroWord;
    end else if(raddr2 == `RegNumLog2'h0) begin
        rdata2 <= `ZeroWord;
    end else if((raddr2 == waddr)&&(we == `WriteEnable)&&(re2 == `ReadEnable)) begin
        rdata2 <= wdata;
    end else if(re2 == `ReadEnable) begin
        rdata2 <= regs[raddr2];
    end else begin
        rdata2 <= `ZeroWord;
    end
end
endmodule


module id (
    input wire rst,
    input wire[`InstAddrBus] pc_i,          //译码阶段指令对应的地址，32
    input wire[`InstBus] inst_i,            //译码阶段的指令，32

    //读取的Regfile的值
    input wire[`RegBus] reg1_data_i,        //Regfile输入的第一个读寄存器端口的输入
    input wire[`RegBus] reg2_data_i,

    //输出到Regfile的信息
    output reg reg1_read_o,                 //Regfile第一个读寄存器端口的读使能信号，1
    output reg reg2_read_o,
    output reg[`RegAddrBus] reg1_addr_o,    //Regfile第一个读寄存器端口的读地址信号，5
    output reg[`RegAddrBus] reg2_addr_o,
    
    //送到执行阶段的信息
    output reg[`AluOpBus] aluop_o,          //译码阶段指令要进行的运算子类型，8
    output reg[`AluSelBus] alusel_o,        //运算类型，3
    output reg[`RegBus] reg1_o,             //源操作数，32
    output reg[`RegBus] reg2_o,
    output reg[`RegAddrBus] wd_o,           //要写入的目的寄存器地址，5
    output reg wreg_o                       //是否要写入的目的寄存器，1
);


    //取得指令码，功能码
    //对于ori指令只需通过判断第26-31bit的值（rs,rt）即可判断是否为ori指令
    wire[5:0 ] op = inst_i[31:26];          //区分指令大类（R型、I型）
    wire[4:0 ] op2 = inst_i[10:6];          //偏移量
    wire[5:0 ] op3 = inst_i[5:0];           //区分指令小类（加减乘除）
    wire[4:0 ] op4 = inst_i[20:16];         //表示不同寄存器
    
    //保存指令执行需要的立即数
    reg[`RegBus] imm;

    //指示指令是否有效
    reg instvalid;


//这个阶段是译码阶段，把操作数，存储运算结果的地址，运算类型找出来
always @(*) begin
    if(rst ==`RstEnable) begin
        aluop_o <= `EXE_NOP_OP;             //8'b00000000,运算小类为0
        alusel_o <= `EXE_RES_NOP;           //3'b000，运算大类为0
        wd_o <= `NOPRegAddr;                //5'b00000,目的寄存器地址为0
        wreg_o <=`WriteDisable;             //不写入的目的寄存器
        instvalid <= `InstInValid;            //指令无效
        reg1_read_o <= 1'b0;
        reg2_read_o <= 1'b0;
        reg1_addr_o <= `NOPRegAddr;         //读出Regfile中的地址为0
        reg2_addr_o <= `NOPRegAddr;
        imm <= 32'h0;
    end else begin
        aluop_o <= `EXE_NOP_OP;             
        alusel_o <= `EXE_RES_NOP;
        wd_o <= inst_i[15:11];              //把取值取出的指令写入目的寄存器
        wreg_o <=`WriteDisable;
        instvalid <= `InstInValid;
        reg1_read_o <= 1'b0;
        reg2_read_o <= 1'b0;
        reg1_addr_o <= inst_i[25:21];       //rs，通过Regfile读端口1读取出的寄存器地址
        reg2_addr_o <= inst_i[20:16];       //rt
        imm <= `ZeroWord;

        //0-15为immediate，提供第二个操作数，需要扩展到32位参与或运算
        //16-20为rt，目标寄存器，存储运算结果
        //21-25为rs，源寄存器1，提供第一个操作数
        //26-31为ORI（001101），识别ORI指令
        case (op)
        `EXE_ORI: begin                     //依据op的值判断是否是ori指令
        wreg_o <=`WriteEnable;              //ori指令需要将结果写入目的寄存器
        aluop_o <= `EXE_OR_OP;              //运算的子类型为逻辑或,6'b001101
        alusel_o <= `EXE_RES_LOGIC;         //运算类型为逻辑运算
        reg1_read_o <= 1'b1;                //需通过Regfile的读端口1读取寄存器
        reg2_read_o <= 1'b0;
        imm <= {16'h0,inst_i[15:0]};        //指令执行需要的立即数，扩展为32位
        wd_o <= inst_i[20:16];              //这个阶段预约了写地址，在WB阶段写入
        instvalid <= `InstValid;            //ori指令是有效指令
        end
        default:begin
        end
        endcase                             //case op
        end                                 //if
end                                         //always


//给出源操作数1的值(reg1_data_i)，用reg1_o传给执行阶段
always @(*) begin
    if(rst == `RstEnable) begin
        reg1_o <= `ZeroWord;
    end else if(reg1_read_o == 1'b1) begin  //若读端口1的信号为1
        reg1_o <= reg1_data_i;              //则Regfile读端口1的输出值作为源操作数
    end else if(reg1_read_o == 1'b0) begin
        reg1_o <= imm;                      //立即数
    end else begin
        reg1_o <= `ZeroWord;
    end
end


//给出源操作数2的值(imm)
always @(*) begin
        if(rst == `RstEnable) begin
        reg2_o <= `ZeroWord;
    end else if(reg2_read_o == 1'b1) begin
        reg2_o <= reg2_data_i;              //Regfile读端口2的输出值
    end else if(reg2_read_o == 1'b0) begin
        reg2_o <= imm;                      //立即数做源操作数2
    end else begin
        reg2_o <= `ZeroWord;
    end
end

endmodule


module id_ex (
    input wire clk,
    input wire rst,

    //从译码阶段传递过来的信息
    input wire[`AluOpBus] id_aluop,
    input wire[`AluSelBus] id_alusel,
    input wire[`RegBus] id_reg1,
    input wire[`RegBus] id_reg2,
    input wire[`RegAddrBus] id_wd,
    input wire id_wreg,

    //传递到执行阶段的信息
    output reg[`AluOpBus] ex_aluop,
    output reg[`AluSelBus] ex_alusel,
    output reg[`RegBus] ex_reg1,
    output reg[`RegBus] ex_reg2,
    output reg[`RegAddrBus] ex_wd,
    output reg ex_wreg
);
    

always @(posedge clk) begin
    if(rst == `RstEnable) begin
        ex_aluop <= `EXE_NOP_OP;
        ex_alusel <= `EXE_RES_NOP;
        ex_reg1 <= `ZeroWord;
        ex_reg2 <= `ZeroWord;
        ex_wd <= `NOPRegAddr;
        ex_wreg <= `WriteDisable;
    end else begin
        ex_aluop <= id_aluop;
        ex_alusel <= id_alusel;
        ex_reg1 <= id_reg1;
        ex_reg2 <= id_reg2;
        ex_wd <= id_wd;
        ex_wreg <= id_wreg;
    end
    end

endmodule


module ex (
    input wire rst,

    //译码阶段送到执行阶段的信息
    input wire[`AluOpBus] aluop_i,
    input wire[`AluSelBus] alusel_i,
    input wire[`RegBus] reg1_i,
    input wire[`RegBus] reg2_i,
    input wire[`RegAddrBus] wd_i,
    input wire wreg_i,

    //执行的结果
    output reg[`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg[`RegBus] wdata_o
);
    
    //保存逻辑运算的结果
    reg[`RegBus] logicout;


always @(*) begin
    if(rst == `RstEnable) begin
        logicout <= `ZeroWord;
    end else begin
        case (aluop_i)
            `EXE_OR_OP:begin
                logicout <= reg1_i | reg2_i;
            end
            default: begin
                logicout <= `ZeroWord;
            end
        endcase
    end
end


always @(*) begin
    wd_o <= wd_i;                       //要写的目的寄存器地址
    wreg_o <= wreg_i;                   //是否要写目的寄存器
    case (alusel_i)                     
        `EXE_RES_LOGIC: begin
            wdata_o <= logicout;        //存放运算结果
        end
        default: begin
            wdata_o <= `ZeroWord;
        end
    endcase
end


endmodule


module ex_mem (
    input wire clk,
    input wire rst,

    //来自执行阶段的信息
    input wire[`RegAddrBus] ex_wd,
    input wire ex_wreg,
    input wire[`RegBus] ex_wdata,

    //送到访存阶段的信息
    output reg[`RegAddrBus] mem_wd,
    output reg mem_wreg,
    output reg[`RegBus] mem_wdata
);
    

always @(posedge clk) begin
    if(rst == `RstEnable) begin
        mem_wd <= `NOPRegAddr;
        mem_wreg <= `WriteDisable;
        mem_wdata <=`ZeroWord;
    end else begin
        mem_wd <= ex_wd;
        mem_wreg <= ex_wreg;
        mem_wdata <= ex_wdata;
    end
end


endmodule


module mem (
    input wire rst,

    //来自执行阶段的信息
    input wire[`RegAddrBus] wd_i,
    input wire wreg_i,
    input wire[`RegBus] wdata_i,

    //访存阶段的结果
    output reg[`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg[`RegBus] wdata_o
);
    

always @(*) begin
    if(rst == `RstEnable) begin
        wd_o <= `NOPRegAddr;
        wreg_o <= `WriteDisable;
        wdata_o <= `ZeroWord;
    end else begin
        wd_o <= wd_i;
        wreg_o <= wreg_i;
        wdata_o <= wdata_i;
    end
end

endmodule


module mem_wb (
    input wire clk,
    input wire rst,

    //访存阶段的结果
    input wire[`RegAddrBus] mem_wd,
    input wire mem_wreg,
    input wire[`RegBus] mem_wdata,

    //送到回写阶段的信息
    output reg[`RegAddrBus] wb_wd,
    output reg wb_wreg,
    output reg[`RegBus] wb_wdata
);
    

always @(posedge clk) begin
    if(rst == `RstEnable) begin
        wb_wd <= `NOPRegAddr;
        wb_wreg <= `WriteDisable;
        wb_wdata <= `ZeroWord;
    end else begin
        wb_wd <= mem_wd;
        wb_wreg <= mem_wreg;
        wb_wdata <= mem_wdata;
    end
end

endmodule

