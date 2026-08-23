// ============================================================================
// TPIPELINE - Active Minimal Datapath Top
// Description: Connects the fork's active trading pipeline:
//              RX frame -> parser -> order book -> market maker -> risk -> TX
//
// This top intentionally excludes the inherited AI, transformer, session
// override, and multi-strategy SmartNIC paths. The goal is a small datapath
// that can be made correct under backpressure and order-book hazards.
// ============================================================================

module tpipeline_top
    import fixed_point_pkg::*;
#(
    // ---- Order Book Parameters ----
    parameter OB_MAX_LEVELS     = 16,
    parameter OB_MAX_ORDERS     = 1024,

    // ---- Market Maker Parameters ----
    parameter MM_SPREAD_TARGET  = 32'd2,
    parameter MM_POSITION_LIMIT = 32'd1000,
    parameter MM_SKEW_SHIFT     = 4,

    // ---- Risk Parameters ----
    parameter RISK_MAX_POSITION = 32'd1000,
    parameter RISK_MAX_NOTIONAL = 32'd10000000,
    parameter RISK_MAX_RATE     = 32'd1000,
    parameter RISK_PRICE_BAND   = 32'd100
)(
    // ---- Clock & Reset ----
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,

    // ---- RX Stream ----
    input  logic [63:0] rx_tdata,
    input  logic        rx_tvalid,
    output logic        rx_tready,
    input  logic        rx_tlast,
    input  logic [7:0]  rx_tkeep,

    // ---- TX Stream ----
    output logic [63:0] tx_tdata,
    output logic        tx_tvalid,
    input  logic        tx_tready,
    output logic        tx_tlast,
    output logic [7:0]  tx_tkeep,

    // ---- Control ----
    input  logic        kill_switch,

    // ---- Status & Diagnostics ----
    output logic signed [31:0] position_out,
    output logic [31:0]        reject_count_out,
    output logic [63:0]        orders_sent_out,
    output logic [63:0]        last_order_id_out,
    output logic               quoting_active_out,
    output logic [7:0]         bid_depth_out,
    output logic [7:0]         ask_depth_out,
    output logic [63:0]        parsed_count_out,
    output logic [63:0]        book_update_count_out,
    output logic [63:0]        risk_approved_count_out,

    // ---- LED Indicators ----
    output logic [3:0]         led_status
);

    // ---- Free-Running Timestamp Counter ----
    logic [63:0] timestamp_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timestamp_counter <= '0;
        else
            timestamp_counter <= timestamp_counter + 1;
    end

    // ---- Stage 1: Parser Outputs ----
    parsed_msg_t parsed_msg;
    logic        parsed_valid;

    // ---- Stage 2: Order Book Outputs ----
    top_of_book_t tob;
    logic         tob_valid;
    logic [7:0]   bid_depth, ask_depth;

    // ---- Stage 3: Strategy Outputs ----
    order_out_t mm_bid_order, mm_ask_order;
    logic       mm_orders_valid;
    logic signed [31:0] mm_position;
    logic       mm_quoting;

    // ---- Stage 4: Risk Outputs ----
    order_out_t   risk_order;
    logic         risk_approved;
    risk_status_t risk_status;
    logic [31:0]  reject_count;
    logic [31:0]  order_count_window;

    // ---- Stage 5: TX Outputs ----
    logic [63:0] orders_sent;
    logic [63:0] last_oid;

    // ---- Diagnostic Counters ----
    logic [63:0] parsed_count;
    logic [63:0] book_update_count;
    logic [63:0] risk_approved_count;
    logic        risk_approved_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parsed_count        <= '0;
            book_update_count   <= '0;
            risk_approved_count <= '0;
            risk_approved_d     <= 1'b0;
        end else if (enable) begin
            risk_approved_d <= risk_approved;

            if (parsed_valid)
                parsed_count <= parsed_count + 1;
            if (tob_valid)
                book_update_count <= book_update_count + 1;
            if (risk_approved && !risk_approved_d)
                risk_approved_count <= risk_approved_count + 1;
        end else begin
            risk_approved_d <= 1'b0;
        end
    end

    // ---- Stage 1: Parser ----
    market_data_parser u_parser (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .s_axis_tdata   (rx_tdata),
        .s_axis_tvalid  (rx_tvalid),
        .s_axis_tready  (rx_tready),
        .s_axis_tlast   (rx_tlast),
        .s_axis_tkeep   (rx_tkeep),
        .parsed_msg     (parsed_msg),
        .parsed_valid   (parsed_valid)
    );

    // ---- Stage 2: Order Book ----
    order_book #(
        .MAX_LEVELS     (OB_MAX_LEVELS),
        .MAX_ORDERS     (OB_MAX_ORDERS)
    ) u_order_book (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .msg_in         (parsed_msg),
        .msg_valid      (parsed_valid),
        .tob            (tob),
        .tob_valid      (tob_valid),
        .bid_depth      (bid_depth),
        .ask_depth      (ask_depth)
    );

    // ---- Stage 3: Deterministic Market Maker ----
    market_maker #(
        .SPREAD_TARGET    (MM_SPREAD_TARGET),
        .POSITION_LIMIT   (MM_POSITION_LIMIT),
        .SKEW_SHIFT       (MM_SKEW_SHIFT)
    ) u_market_maker (
        .clk              (clk),
        .rst_n            (rst_n),
        .enable           (enable),
        .tob              (tob),
        .tob_valid        (tob_valid),
        .fill_valid       (1'b0),
        .fill_side        (8'h42),
        .fill_qty         (32'd0),
        .bid_order        (mm_bid_order),
        .ask_order        (mm_ask_order),
        .orders_valid     (mm_orders_valid),
        .current_position (mm_position),
        .quoting_active   (mm_quoting)
    );

    // This baseline path only transmits the bid quote. The next strategy
    // cleanup will add an explicit quote scheduler/FIFO before risk.
    order_out_t strategy_order;
    logic       strategy_valid;

    always_comb begin
        strategy_order = '0;
        strategy_valid = 1'b0;

        if (mm_orders_valid) begin
            strategy_order = mm_bid_order;
            strategy_valid = 1'b1;
        end
    end

    // ---- Stage 4: Risk Gate ----
    risk_manager #(
        .MAX_POSITION       (RISK_MAX_POSITION),
        .MAX_NOTIONAL       (RISK_MAX_NOTIONAL),
        .MAX_ORDERS_PER_SEC (RISK_MAX_RATE),
        .PRICE_BAND_TICKS   (RISK_PRICE_BAND)
    ) u_risk_manager (
        .clk                (clk),
        .rst_n              (rst_n),
        .enable             (enable),
        .order_in           (strategy_order),
        .order_valid        (strategy_valid),
        .current_position   (mm_position),
        .reference_price    (tob.mid_price),
        .kill_switch        (kill_switch),
        .order_out          (risk_order),
        .order_approved     (risk_approved),
        .risk_status        (risk_status),
        .reject_count       (reject_count),
        .order_count_window (order_count_window)
    );

    // ---- Stage 5: Order Generator ----
    order_generator u_order_gen (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (enable),
        .order_in          (risk_order),
        .order_valid       (risk_approved),
        .timestamp         (timestamp_counter),
        .m_axis_tdata      (tx_tdata),
        .m_axis_tvalid     (tx_tvalid),
        .m_axis_tready     (tx_tready),
        .m_axis_tlast      (tx_tlast),
        .m_axis_tkeep      (tx_tkeep),
        .orders_sent_count (orders_sent),
        .last_order_id     (last_oid)
    );

    // ---- Status Outputs ----
    assign position_out            = mm_position;
    assign reject_count_out        = reject_count;
    assign orders_sent_out         = orders_sent;
    assign last_order_id_out       = last_oid;
    assign quoting_active_out      = mm_quoting;
    assign bid_depth_out           = bid_depth;
    assign ask_depth_out           = ask_depth;
    assign parsed_count_out        = parsed_count;
    assign book_update_count_out   = book_update_count;
    assign risk_approved_count_out = risk_approved_count;

    // ---- LED Indicators ----
    assign led_status[0] = enable;
    assign led_status[1] = mm_quoting;
    assign led_status[2] = risk_status.circuit_breaker;
    assign led_status[3] = |reject_count[3:0];

endmodule
