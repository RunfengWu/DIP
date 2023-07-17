//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           cmos_capture_data
// Last modified Date:  2020/05/04 9:19:08
// Last Version:        V1.0
// Descriptions:        摄像头采集模块
//                      
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/05/04 9:19:08
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------

//将摄像头采集的8位数据转换为16位RGB565格式
//****************************************************************************************//
module cmos_capture_data(
    input                 rst_n            ,  //复位信号    
    //摄像头接口                           
    input                 cam_pclk         ,  //cmos 数据像素时钟
    input                 cam_vsync        ,  //cmos 场同步信号
    input                 cam_href         ,  //cmos 行同步信号
    input  [7:0]          cam_data         ,                      
    //用户接口                              
    output                cmos_frame_vsync ,  //帧有效信号    
    output                cmos_frame_href  ,  //行有效信号
    output                cmos_frame_valid ,  //数据有效使能信号
    output       [15:0]   cmos_frame_data     //有效数据        
    );

//寄存器全部配置完成后，先等待10帧数据
//待寄存器配置生效后再开始采集图像
parameter  WAIT_FRAME = 4'd10    ;            //寄存器数据稳定等待的帧个数，抛弃前十帧数据（摄像头要求）
							     
//reg define                     
reg             cam_vsync_d0     ;
reg             cam_vsync_d1     ;
reg             cam_href_d0      ;
reg             cam_href_d1      ;
reg    [3:0]    cmos_ps_cnt      ;            //等待帧数稳定计数器
reg    [7:0]    cam_data_d0      ;            
reg    [15:0]   cmos_data_t      ;            //用于8位转16位的临时寄存器
reg             byte_flag        ;            //16位RGB数据转换完成的标志信号
reg             byte_flag_d0     ;
reg             frame_val_flag   ;            //帧有效的标志 

wire            pos_vsync        ;            //采输入场同步信号的上升沿

//*****************************************************
//**                    main code
//*****************************************************

//************************************************************ 行场信号同步，其他使能信号 ************************************************************//
//采输入场同步信号的上升沿
assign pos_vsync = (~cam_vsync_d1) & cam_vsync_d0;                          //采输入场同步信号的上升沿

//输出帧有效信号，保证帧信号同步
assign  cmos_frame_vsync = frame_val_flag  ?  cam_vsync_d1  :  1'b0;        //帧信号打两拍同步
//输出行有效信号，保证行信号同步
assign  cmos_frame_href  = frame_val_flag  ?  cam_href_d1   :  1'b0;        //行信号打两拍同步

//输出数据使能有效信号
assign  cmos_frame_valid = frame_val_flag  ?  byte_flag_d0  :  1'b0;        //当数据转换完成时，输出数据使能信号

//输出数据
assign  cmos_frame_data  = frame_val_flag  ?  cmos_data_t   :  1'b0;        //当数据转换完成时，输出数据
       
//对行场信号进行打拍，确保行场信号同步
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        cam_vsync_d0 <= 1'b0;
        cam_vsync_d1 <= 1'b0;
        cam_href_d0 <= 1'b0;
        cam_href_d1 <= 1'b0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;
        cam_vsync_d1 <= cam_vsync_d0;
        cam_href_d0 <= cam_href;
        cam_href_d1 <= cam_href_d0;
    end
end
//************************************************************ 行场信号同步，其他使能信号 ************************************************************//


//******************************************************** 采样延迟，延迟10个数据（摄像头要求） ********************************************************//
//对帧数进行计数
always @(posedge cam_pclk or negedge rst_n) begin                           
    if(!rst_n)
        cmos_ps_cnt <= 4'd0;
    else if(pos_vsync && (cmos_ps_cnt < WAIT_FRAME)) 
        cmos_ps_cnt <= cmos_ps_cnt + 4'd1;
end

//帧有效标志
always @(posedge cam_pclk or negedge rst_n) begin                           //延迟结束后，开始采集图像（帧有效）
    if(!rst_n)
        frame_val_flag <= 1'b0;
    else if((cmos_ps_cnt == WAIT_FRAME) && pos_vsync)
        frame_val_flag <= 1'b1;
    else;    
end            
//******************************************************** 采样延迟，延迟10个数据（摄像头要求） ********************************************************//


//************************************************************ 8位数据拼接成16位RGB565数据 ***********************************************************//
//8位数据转16位RGB565数据        
always @(posedge cam_pclk or negedge rst_n) begin                           //8位数据转16位RGB565数据
    if(!rst_n) begin
        cmos_data_t <= 16'd0;
        cam_data_d0 <= 8'd0;
        byte_flag <= 1'b0;
    end
    else if(cam_href) begin
        byte_flag <= ~byte_flag;                                            //二分频拼接
        cam_data_d0 <= cam_data;
        if(byte_flag)
            cmos_data_t <= {cam_data_d0,cam_data};                          //前拍数据作为低8位，后拍数据作为高8位
        else;   
    end
    else begin
        byte_flag <= 1'b0;
        cam_data_d0 <= 8'b0;
    end    
end        
//************************************************************ 8位数据拼接成16位RGB565数据 ***********************************************************//


//产生输出数据有效信号(cmos_frame_valid)
always @(posedge cam_pclk or negedge rst_n) begin                           //拼接完成后，输出数据使能信号
    if(!rst_n)
        byte_flag_d0 <= 1'b0;
    else
        byte_flag_d0 <= byte_flag;	                                        //信号输出信号，16位RGB565数据拼接完成
end 
       
endmodule