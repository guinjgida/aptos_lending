module alcove::Helper {

    use alcove::Price;

    public fun token_market_value<CoinType>(amount: u64): u64 {
        // get price of token<CoinType>
        // calc amount * price
        let price_of_coin = Price::price<CoinType>();
        amount * price_of_coin
    }}