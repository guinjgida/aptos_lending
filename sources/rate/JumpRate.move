module alcove::JumpRateModel{

    use std::signer;
    use alcove::Config;

    const EINVALID_ADDRESS:u64 = 0;

    struct JumpRateModel<phantom CoinType> has key{
        utilization_optimal:u64,
        reserve_factor:u64,
        base:u64,
        slope_1:u64,
        slope_2:u64
    }

    public fun initialize<CoinType>(
        account:&signer,
        utilization_optimal:u64,
        base:u64,
        reserve_factor:u64,
        slope_1:u64,
        slope_2:u64
    ){
        assert!(Config::admin_address() == signer::address_of(account),EINVALID_ADDRESS);
        move_to(account,JumpRateModel<CoinType>{
            utilization_optimal,
            reserve_factor,
            base,
            slope_1,
            slope_2
        });
    }
    public fun borrow_rate<CoinType>(utilization_rate:u64):u64 acquires JumpRateModel{
        let (utilization_optimal,_reserve_factor,base,slope_1,slope_2) = get_model<CoinType>();
        let rate = if (utilization_rate <= utilization_optimal){
            let u_s = utilization_rate*slope_1;
            let u_s_o = u_s / (1 - utilization_optimal);
            base+u_s_o
        }else {
            let u_s = (utilization_rate - utilization_optimal) * slope_2;
            let u_s_o = u_s / (1 - utilization_optimal);
            let b_s = base + slope_1;
            b_s + u_s_o
        };
        rate
    }

    public fun deposit_rate<CoinType>(utilization_rate:u64,borrow_rate:u64):u64 acquires JumpRateModel{
        let (_utilization_optimal,reserve_factor,_base,_slope_1,_slope_2) = get_model<CoinType>();
        let reserve_factor_ = 1 - reserve_factor;
        let r_u = borrow_rate * utilization_rate;
        let rate = r_u * reserve_factor_;
        rate
    }

    public fun reserve_factor<CoinType>(): u64 acquires JumpRateModel {
        let (_utilization_optimal,
            reserve_factor,
            _base,
            _slope_1,
            _slope_2) = get_model<CoinType>();
        reserve_factor
    }

    public fun get_model<CoinType>():(u64,u64,u64,u64,u64)acquires JumpRateModel{
        let config = borrow_global<JumpRateModel<CoinType>>(Config::admin_address());
        (config.utilization_optimal,config.reserve_factor,config.base,config.slope_1,config.slope_2)
    }

}