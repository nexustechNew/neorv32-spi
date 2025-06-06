-- ================================================================================ --
-- NEORV32 - Simple Combinatorial XBUS / Wishbone Gateway                           --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity xbus_gateway is
  generic (
    -- device enable, address size in bytes and base address (word-aligned) --
    DEV_0_EN : boolean := false; DEV_0_SIZE : natural := 0; DEV_0_BASE : std_ulogic_vector(31 downto 0) := (others => '0');
    DEV_1_EN : boolean := false; DEV_1_SIZE : natural := 0; DEV_1_BASE : std_ulogic_vector(31 downto 0) := (others => '0');
    DEV_2_EN : boolean := false; DEV_2_SIZE : natural := 0; DEV_2_BASE : std_ulogic_vector(31 downto 0) := (others => '0');
    DEV_3_EN : boolean := false; DEV_3_SIZE : natural := 0; DEV_3_BASE : std_ulogic_vector(31 downto 0) := (others => '0')
  );
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;
    -- host port --
    host_req_i  : in  xbus_req_t;
    host_rsp_o  : out xbus_rsp_t;
    -- device ports --
    dev_0_req_o : out xbus_req_t; dev_0_rsp_i : in xbus_rsp_t;
    dev_1_req_o : out xbus_req_t; dev_1_rsp_i : in xbus_rsp_t;
    dev_2_req_o : out xbus_req_t; dev_2_rsp_i : in xbus_rsp_t;
    dev_3_req_o : out xbus_req_t; dev_3_rsp_i : in xbus_rsp_t
  );
end xbus_gateway;

architecture xbus_gateway_rtl of xbus_gateway is

  -- module configuration --
  constant num_devs_c : natural := 4; -- number of device ports

  -- list of device base address and address size --
  type dev_en_list_t   is array (0 to num_devs_c-1) of boolean;
  type dev_base_list_t is array (0 to num_devs_c-1) of std_ulogic_vector(31 downto 0);
  type dev_size_list_t is array (0 to num_devs_c-1) of natural;
  constant dev_en_list_c   : dev_en_list_t   := (DEV_0_EN, DEV_1_EN, DEV_2_EN, DEV_3_EN);
  constant dev_base_list_c : dev_base_list_t := (DEV_0_BASE, DEV_1_BASE, DEV_2_BASE, DEV_3_BASE);
  constant dev_size_list_c : dev_size_list_t := (DEV_0_SIZE, DEV_1_SIZE, DEV_2_SIZE, DEV_3_SIZE);

  -- device ports combined as arrays --
  type dev_req_t is array (0 to num_devs_c-1) of xbus_req_t;
  type dev_rsp_t is array (0 to num_devs_c-1) of xbus_rsp_t;
  signal dev_req : dev_req_t;
  signal dev_rsp : dev_rsp_t;

  -- device access --
  signal acc_en  : std_ulogic_vector(num_devs_c-1 downto 0);
  signal acc_err : std_ulogic;

begin

  -- combine device ports --
  dev_0_req_o <= dev_req(0); dev_rsp(0) <= dev_0_rsp_i;
  dev_1_req_o <= dev_req(1); dev_rsp(1) <= dev_1_rsp_i;
  dev_2_req_o <= dev_req(2); dev_rsp(2) <= dev_2_rsp_i;
  dev_3_req_o <= dev_req(3); dev_rsp(3) <= dev_3_rsp_i;

  -- device select --
  acc_en_gen:
  for i in 0 to num_devs_c-1 generate
    acc_en(i) <= '1' when (dev_size_list_c(i) > 0) and dev_en_list_c(i) and
                          (unsigned(host_req_i.addr) >= unsigned(dev_base_list_c(i))) and
                          (unsigned(host_req_i.addr) < (unsigned(dev_base_list_c(i)) + dev_size_list_c(i))) else '0';
  end generate;

  -- invalid access address --
  err_gen: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      acc_err <= '0';
    elsif rising_edge(clk_i) then
      acc_err <= host_req_i.stb and host_req_i.cyc and (not or_reduce_f(acc_en));
    end if;
  end process err_gen;

  -- request --
  bus_request_gen:
  for i in 0 to num_devs_c-1 generate
    bus_request: process(host_req_i, acc_en)
    begin
      dev_req(i) <= xbus_req_terminate_c; -- default: disabled
      if dev_en_list_c(i) then
        dev_req(i)     <= host_req_i;
        dev_req(i).cyc <= host_req_i.cyc and acc_en(i);
        dev_req(i).stb <= host_req_i.stb and acc_en(i);
      end if;
    end process bus_request;
  end generate;

  -- response --
  bus_response: process(acc_err, dev_rsp, acc_en)
    variable tmp_v : xbus_rsp_t;
  begin
    tmp_v.data := (others => '0');
    tmp_v.ack  := '0';
    tmp_v.err  := acc_err;
    for i in 0 to num_devs_c-1 loop -- OR all enabled response buses
      if (acc_en(i) = '1') and dev_en_list_c(i) then
        tmp_v.data := tmp_v.data or dev_rsp(i).data;
        tmp_v.ack  := tmp_v.ack  or dev_rsp(i).ack;
        tmp_v.err  := tmp_v.err  or dev_rsp(i).err;
      end if;
    end loop;
    host_rsp_o <= tmp_v;
  end process bus_response;

end xbus_gateway_rtl;
