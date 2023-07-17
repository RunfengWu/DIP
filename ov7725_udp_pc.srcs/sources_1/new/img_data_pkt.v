//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com 
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           img_data_pkt
// Last modified Date:  2020/2/18 9:20:14
// Last Version:        V1.0
// Descriptions:        图像封装模块(添加帧头)    
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2020/2/18 9:20:14
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------

//将16位RGB565格式拼接为32位，并加上帧头和图像分辨率，传输给以太网模块
//****************************************************************************************//

module img_data_pkt(
    input                 rst_n          ,   //复位信号，低电平有效
    //图像相关信号
    input                 cam_pclk       ,   //像素时钟
    input                 img_vsync      ,   //帧同步信号
    input                 img_data_en    ,   //数据有效使能信号
    input        [15:0]   img_data       ,   //有效数据 
    
    input                 transfer_flag  ,   //图像开始传输标志,1:开始传输 0:停止传输
    //以太网相关信号 
    input                 eth_tx_clk     ,   //以太网发送时钟
    input                 udp_tx_req     ,   //udp发送数据请求信号
    input                 udp_tx_done    ,   //udp发送数据完成信号                               
    output  reg           udp_tx_start_en,   //udp开始发送信号
    output       [31:0]   udp_tx_data    ,   //udp发送的数据
    output  reg  [15:0]   udp_tx_byte_num    //udp单包发送的有效字节数
    );    
    
//parameter define
parameter  CMOS_H_PIXEL = 16'd640;  //图像水平方向分辨率
parameter  CMOS_V_PIXEL = 16'd480;  //图像垂直方向分辨率
//图像帧头,用于标志一帧数据的开始
parameter  IMG_FRAME_HEAD = {32'hf0_5a_a5_0f};      //帧头

reg             img_vsync_d0    ;  //帧有效信号打拍
reg             img_vsync_d1    ;  //帧有效信号打拍
reg             neg_vsync_d0    ;  //帧有效信号下降沿打拍
                                
reg             wr_sw           ;  //用于位拼接的标志
reg    [15:0]   img_data_d0     ;  //有效图像数据打拍
reg             wr_fifo_en      ;  //写fifo使能
reg    [31:0]   wr_fifo_data    ;  //写fifo数据

reg             img_vsync_txc_d0;  //以太网发送时钟域下,帧有效信号打拍
reg             img_vsync_txc_d1;  //以太网发送时钟域下,帧有效信号打拍
reg             tx_busy_flag    ;  //发送忙信号标志
                                
//wire define                   
wire            pos_vsync       ;  //帧有效信号上升沿
wire            neg_vsync       ;  //帧有效信号下降沿
wire            neg_vsynt_txc   ;  //以太网发送时钟域下,帧有效信号下降沿
wire   [9:0]    fifo_rdusedw    ;  //当前FIFO缓存的个数

//*****************************************************
//**                    main code
//*****************************************************

//信号采沿
assign neg_vsync = img_vsync_d1 & (~img_vsync_d0);                  //像素时钟域下的帧下降沿
assign pos_vsync = ~img_vsync_d1 & img_vsync_d0;                    //像素时钟域下的帧上升沿
assign neg_vsynt_txc = img_vsync_txc_d1 & (~img_vsync_txc_d0);      //以太网时钟域下的帧下降沿

//对img_vsync信号延时两个时钟周期,用于采沿
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        img_vsync_d0 <= 1'b0;
        img_vsync_d1 <= 1'b0;
    end
    else begin
        img_vsync_d0 <= img_vsync;
        img_vsync_d1 <= img_vsync_d0;
    end
end

//以太网发送时钟域下,对img_vsync信号延时两个时钟周期,用于采沿
always @(posedge eth_tx_clk or negedge rst_n) begin
    if(!rst_n) begin
        img_vsync_txc_d0 <= 1'b0;
        img_vsync_txc_d1 <= 1'b0;
    end
    else begin
        img_vsync_txc_d0 <= img_vsync;
        img_vsync_txc_d1 <= img_vsync_txc_d0;
    end
end


//********************************************************************* 像素时钟域下的信号处理 *********************************************************************//
//寄存neg_vsync信号(下降沿)，用于控制帧头和图像分辨率的写入
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) 
        neg_vsync_d0 <= 1'b0;
    else 
        neg_vsync_d0 <= neg_vsync;
end    

//对wr_sw和img_data_d0信号赋值,用于位拼接
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        wr_sw <= 1'b0;
        img_data_d0 <= 1'b0;
    end
    else if(neg_vsync)                                  //先写帧头，再写图像分辨率，最后才写图像数据
        wr_sw <= 1'b0;
    else if(img_data_en) begin                          //类似cmos_capture_data模块中8位数据扩展成16位RGB565格式的操作
        wr_sw <= ~wr_sw;                                //二分频，用于拼接成32位数据
        img_data_d0 <= img_data;
    end    
end 

//将帧头和图像数据写入FIFO，每当帧有效时，依次为：帧头、图像分辨率、图像数据
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        wr_fifo_en <= 1'b0;
        wr_fifo_data <= 1'b0;
    end
    else begin
        if(neg_vsync) begin                               //帧下降沿控制写帧头
            wr_fifo_en <= 1'b1;
            wr_fifo_data <= IMG_FRAME_HEAD;               //帧头
        end
        else if(neg_vsync_d0) begin                       //打一拍帧下降沿控制写图像分辨率
            wr_fifo_en <= 1'b1;
            wr_fifo_data <= {CMOS_H_PIXEL,CMOS_V_PIXEL};  //水平和垂直方向分辨率
        end
        else if(img_data_en && wr_sw) begin               //图像数据使能，且wr_sw为1时（完成寄存），将16位RGB数据拼接成32位数据写入FIFO
            wr_fifo_en <= 1'b1;
            wr_fifo_data <= {img_data_d0,img_data};       //图像数据位拼接,16位转32位
          end
        else begin
            wr_fifo_en <= 1'b0;
            wr_fifo_data <= 1'b0;        
        end
    end
end


//********************************************************************* 以太网时钟域下的信号处理 *********************************************************************//
//控制以太网发送的字节数
always @(posedge eth_tx_clk or negedge rst_n) begin
    if(!rst_n)
        udp_tx_byte_num <= 1'b0;
    else if(neg_vsynt_txc)                                  //以太网发送时钟域下，帧第一行需要发送数据的字节数（包括帧头和行场分辨率）
        udp_tx_byte_num <= {CMOS_H_PIXEL,1'b0} + 16'd8;     //发送一帧数据，字节数为：640*2bit+8bit（包括8bit的帧头和行场分辨率）
    else if(udp_tx_done)                                    //udp发送一行数据完成信号
        udp_tx_byte_num <= {CMOS_H_PIXEL,1'b0};             //发送完成后，对udp_tx_byte_num赋值1280（640*2bit）
end

//控制以太网发送开始信号
always @(posedge eth_tx_clk or negedge rst_n) begin
    if(!rst_n) begin
        udp_tx_start_en <= 1'b0;
        tx_busy_flag <= 1'b0;
    end
    //上位机未发送"开始"命令时,以太网不发送图像数据
    else if(transfer_flag == 1'b0) begin
        udp_tx_start_en <= 1'b0;
        tx_busy_flag <= 1'b0;        
    end
    else begin
        udp_tx_start_en <= 1'b0;
        //当FIFO中的个数满足需要发送的字节数时
        if(tx_busy_flag == 1'b0 && fifo_rdusedw >= udp_tx_byte_num[15:2]) begin     //FIFO存储的数据个数大于等于需要发送的字节数（一行），FIFO数据以Byte存储，但发送是以字节计数，所以需要除以4（将8位转换成32位）
            udp_tx_start_en <= 1'b1;                     //开始控制发送一包数据
            tx_busy_flag <= 1'b1;
        end
        else if(udp_tx_done || neg_vsynt_txc) 
            tx_busy_flag <= 1'b0;
    end
end

//异步FIFO，将拼接好的数据存入FIFO，以太网发送时钟域下读取数据（跨时钟域）
async_fifo_1024x32b async_fifo_1024x32b_inst (
  .rst(pos_vsync | (~transfer_flag)), // FIFO复位控制
  .wr_clk(cam_pclk),                  // FIFO写时钟
  .rd_clk(eth_tx_clk),                // FIFO读时钟
  .din(wr_fifo_data),                 // FIFO写数据
  .wr_en(wr_fifo_en),                 // FIFO写使能
  .rd_en(udp_tx_req),                 // FIFO读使能
  .dout(udp_tx_data),                 // FIFO读数据
  .full(),                       
  .empty(),                 
  .rd_data_count(fifo_rdusedw),       // FIFO读侧数据个数
  .wr_rst_busy(),      
  .rd_rst_busy()     
);   

endmodule