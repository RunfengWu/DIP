//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com 
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           ov7725_udp_pc
// Last modified Date:  2020/2/18 9:20:14
// Last Version:        V1.0
// Descriptions:        OV7725以太网传输视频顶层模块
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2020/2/18 9:20:14
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

//例化顶层模块
module ov7725_udp_pc(
    input              sys_clk     , //系统时钟  
    input              sys_rst_n   , //系统复位信号，低电平有效 
    //以太网接口
    input              eth_rxc     , //RGMII接收数据时钟
    input              eth_rx_ctl  , //RGMII输入数据有效信号
    input       [3:0]  eth_rxd     , //RGMII输入数据
    output             eth_txc     , //RGMII发送数据时钟    
    output             eth_tx_ctl  , //RGMII输出数据有效信号
    output      [3:0]  eth_txd     , //RGMII输出数据          
    output             eth_rst_n   , //以太网芯片复位信号，低电平有效    

    //摄像头接口
    input              cam_pclk    , //cmos 数据像素时钟
    input              cam_vsync   , //cmos 场同步信号
    input              cam_href    , //cmos 行同步信号
    input     [7:0]    cam_data    , //cmos 数据
    output             cam_rst_n   , //cmos 复位信号，低电平有效
    output             cam_sgm_ctrl, //cmos 时钟选择信号, 1:使用摄像头自带的晶振，0：FPGA提供的时钟
    output             cam_scl     , //cmos SCCB_SCL线
    inout              cam_sda       //cmos SCCB_SDA线    
);

//parameter define
//开发板MAC地址 00-11-22-33-44-55
parameter  BOARD_MAC = 48'h00_11_22_33_44_55;     
//开发板IP地址 192.168.1.10
parameter  BOARD_IP  = {8'd192,8'd168,8'd1,8'd10};  
//目的MAC地址 ff_ff_ff_ff_ff_ff
parameter  DES_MAC   = 48'hff_ff_ff_ff_ff_ff;    
//目的IP地址 192.168.1.102     
parameter  DES_IP    = {8'd192,8'd168,8'd1,8'd102};

parameter  SLAVE_ADDR = 7'h21         ;  //OV7725的器件地址7'h21
parameter  BIT_CTRL   = 1'b0          ;  //OV7725的字节地址为8位  0:8位 1:16位
parameter  CLK_FREQ   = 26'd50_000_000;  //i2c_dri模块的驱动时钟频率
parameter  I2C_FREQ   = 18'd250_000   ;  //I2C的SCL时钟频率,不超过400KHz

//wire define
wire            clk_50m         ;   //50Mhz时钟
wire            clk_200m        ;   //200Mhz时钟
wire            eth_tx_clk      ;   //以太网发送时钟
wire            locked          ; 
wire            rst_n           ; 
wire            i2c_dri_clk     ;   //I2C操作时钟
wire            i2c_done        ;   //I2C读写完成信号
wire            i2c_exec        ;   //I2C触发信号
wire   [15:0]   i2c_data        ;   //I2C写地址+数据
wire            cam_init_done   ;   //摄像头出初始化完成信号 
wire            cmos_frame_vsync;   //帧同步信号   
wire            img_data_en     ;   //摄像头图像有效信号
wire   [15:0]   img_data        ;   //摄像头图像有效数据
 
wire            transfer_flag   ;   //图像开始传输标志,0:开始传输 1:停止传输
wire            eth_rx_clk      ;   //以太网接收时钟
wire            udp_tx_start_en ;   //以太网开始发送信号
wire   [15:0]   udp_tx_byte_num ;   //以太网发送的有效字节数
wire   [31:0]   udp_tx_data     ;   //以太网发送的数据    
wire            udp_rec_pkt_done;   //以太网单包数据接收完成信号
wire            udp_rec_en      ;   //以太网接收使能信号
wire   [31:0]   udp_rec_data    ;   //以太网接收到的数据
wire   [15:0]   udp_rec_byte_num;   //以太网接收到的字节个数
wire            udp_tx_req      ;   //以太网发送请求数据信号
wire            udp_tx_done     ;   //以太网发送完成信号

//*****************************************************
//**                    main code
//*****************************************************

assign  rst_n = sys_rst_n & locked;
//不对摄像头硬件复位,固定高电平
assign  cam_rst_n = 1'b1;
//cmos 时钟选择信号, 1:使用摄像头自带的晶振
assign  cam_sgm_ctrl = 1'b1;

//********************************************************************* PLL模块 ********************************************************************//
clk_wiz_0 u_clk_wiz_0
   (
    .clk_out1    (clk_50m),  
    .clk_out2    (clk_200m), 
    .reset       (~sys_rst_n),  
    .locked      (locked),       
    .clk_in1     (sys_clk)
    );      

//******************************************************************* I2C配置模块 *******************************************************************//
i2c_ov7725_rgb565_cfg u_i2c_cfg(
    .clk           (i2c_dri_clk),           //由i2c_dri模块提供的时钟
    .rst_n         (rst_n),
    .i2c_done      (i2c_done),
    .i2c_exec      (i2c_exec),
    .i2c_data      (i2c_data),
    .init_done     (cam_init_done)
    );    

//******************************************************************* I2C驱动模块 ********************************************************************//
i2c_dri 
   #(
    .SLAVE_ADDR  (SLAVE_ADDR),               //参数传递
    .CLK_FREQ    (CLK_FREQ  ),              
    .I2C_FREQ    (I2C_FREQ  )                
    ) 
   u_i2c_dri(
    .clk         (clk_50m   ),               //I2C驱动时钟
    .rst_n       (rst_n     ),   
    //i2c interface
    .i2c_exec    (i2c_exec  ),   
    .bit_ctrl    (BIT_CTRL  ),   
    .i2c_rh_wl   (1'b0),                     //固定为0，只用到了IIC驱动的写操作   
    .i2c_addr    (i2c_data[15:8]),   
    .i2c_data_w  (i2c_data[7:0]),   
    .i2c_data_r  (),   
    .i2c_done    (i2c_done  ),   
    .scl         (cam_scl   ),   
    .sda         (cam_sda   ),   
    //user interface
    .dri_clk     (i2c_dri_clk)               //二分频（25m），作为i2c_ov7725_rgb565_cfg模块的输入时钟，用于配置摄像头寄存器
);

//***************************************************************** 摄像头CMOS采集模块 *****************************************************************//
//8位数据拼接为16位数据过程中时钟域不变
cmos_capture_data u_cmos_capture_data(

    .rst_n              (rst_n & cam_init_done),
    .cam_pclk           (cam_pclk),         //cmos 数据像素时钟，使用摄像头自带的晶振12Mhz
    .cam_vsync          (cam_vsync),
    .cam_href           (cam_href),
    .cam_data           (cam_data),           
    .cmos_frame_vsync   (cmos_frame_vsync),
    .cmos_frame_href    (),
    .cmos_frame_valid   (img_data_en),     
    .cmos_frame_data    (img_data)          //将采集到的数据发送给图像封装模块
    );

//******************************************************************* 图像传输控制模块 ******************************************************************//
start_transfer_ctrl u_start_transfer_ctrl(
    .clk                (eth_rx_clk),       //以太网接收时钟，通过接收数据来控制状态
    .rst_n              (rst_n),
    .udp_rec_pkt_done   (udp_rec_pkt_done),
    .udp_rec_en         (udp_rec_en      ),
    .udp_rec_data       (udp_rec_data    ),
    .udp_rec_byte_num   (udp_rec_byte_num),

    .transfer_flag      (transfer_flag)      //图像开始传输标志,1:开始传输 0:停止传输
    );       
     
//********************************************************************* 图像封装模块 ********************************************************************//
//需要使用异步FIFO实现跨时钟域的数据传输
img_data_pkt u_img_data_pkt(    
    .rst_n              (rst_n),              
   
    .cam_pclk           (cam_pclk),         //cmos 数据写入时钟，使用摄像头自带的晶振12Mhz提供
    .img_vsync          (cmos_frame_vsync),
    .img_data_en        (img_data_en),
    .img_data           (img_data),
    .transfer_flag      (transfer_flag),            
    .eth_tx_clk         (eth_tx_clk     ),  //以太网模块读取数据时钟，时钟由eth_top模块提供
    .udp_tx_req         (udp_tx_req     ),
    .udp_tx_done        (udp_tx_done    ),
    .udp_tx_start_en    (udp_tx_start_en),
    .udp_tx_data        (udp_tx_data    ),
    .udp_tx_byte_num    (udp_tx_byte_num)
    );  

//********************************************************************* 以太网模块 ********************************************************************//
eth_top  #(
    .BOARD_MAC     (BOARD_MAC),              //参数例化
    .BOARD_IP      (BOARD_IP ),          
    .DES_MAC       (DES_MAC  ),          
    .DES_IP        (DES_IP   )          
    )          
    u_eth_top(          
    .sys_rst_n       (rst_n     ),           //系统复位信号，低电平有效           
    .clk_200m        (clk_200m),             //由PLL提供时钟，200Mhz时钟
    //以太网RGMII接口             
    .eth_rxc         (eth_rxc   ),           //RGMII接收数据时钟
    .eth_rx_ctl      (eth_rx_ctl),           //RGMII输入数据有效信号
    .eth_rxd         (eth_rxd   ),           //RGMII输入数据
    .eth_txc         (eth_txc   ),           //RGMII发送数据时钟    
    .eth_tx_ctl      (eth_tx_ctl),           //RGMII输出数据有效信号
    .eth_txd         (eth_txd   ),           //RGMII输出数据          
    .eth_rst_n       (eth_rst_n ),           //以太网芯片复位信号，低电平有效 

    .gmii_rx_clk     (eth_rx_clk),           //GMII接收时钟
    .gmii_tx_clk     (eth_tx_clk),           //GMII发送时钟
    .udp_tx_start_en (udp_tx_start_en),
    .tx_data         (udp_tx_data),
    .tx_byte_num     (udp_tx_byte_num),
    .udp_tx_done     (udp_tx_done),
    .tx_req          (udp_tx_req ),
    .rec_pkt_done    (udp_rec_pkt_done),
    .rec_en          (udp_rec_en      ),
    .rec_data        (udp_rec_data    ),
    .rec_byte_num    (udp_rec_byte_num)
    );

endmodule