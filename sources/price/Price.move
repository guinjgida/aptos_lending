module alcove::Price{
    use alcove::Coin;
    use aptos_std::type_info;
    use aptos_framework::aptos_coin;

    const EINVALID_TOKEN:u64 = 401;

    public fun price<CoinType>():u64{
        if(type_info::type_name<CoinType>() == type_info::type_name<Coin::BTC>()){
            return 1
        };
        if(type_info::type_name<CoinType>() == type_info::type_name<Coin::ETH>()){
            return 1
        };
        if(type_info::type_name<CoinType>() == type_info::type_name<aptos_coin::AptosCoin>()){
            return 1
        };
        assert!(false,EINVALID_TOKEN);
        0
    }
}