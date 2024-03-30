module alcove::Coin{
    use std::signer;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use alcove::Config;

    const MAX_PER_MINT:u64 = 100000;
    const EMINT_AMOUNT_BEYOND:u64 = 1;

    struct BTC has key,store{}

    struct ETH has key,store{}

    struct Cap<phantom CoinType> has key{
        mint_cap:coin::MintCapability<CoinType>,
        freeze_cap:coin::FreezeCapability<CoinType>,
        burn_cap:coin::BurnCapability<CoinType>
    }

    const EINVALID_ADDRESS:u64 = 201;

    public entry fun initialize<CoinType>(
        sender:&signer,
        name:string::String,
        symbol:string::String,
        decimals:u8,
        monitor_supply:bool
    ){
        assert!(signer::address_of(sender) == Config::admin_address(),EINVALID_ADDRESS);

        managed_coin::register<CoinType>(sender);

        let (burn_cap,freeze_cap,mint_cap) = coin::initialize<CoinType>(
            sender,
            name,
            symbol,
            decimals,
            monitor_supply
        );
        move_to(sender,Cap<CoinType>{
            mint_cap,
            freeze_cap,
            burn_cap
        });

    }

    public entry fun mint<CoinType>(
        sender:&signer,
        amount:u64
    )acquires Cap{
        assert!(amount < MAX_PER_MINT,EMINT_AMOUNT_BEYOND);
        let cap = borrow_global<Cap<CoinType>>(Config::admin_address());
        let minted_coins = coin::mint<CoinType>(amount,&cap.mint_cap);
        if (!coin::is_account_registered<CoinType>(signer::address_of(sender))){
            managed_coin::register<CoinType>(sender);
        };
        coin::deposit<CoinType>(signer::address_of(sender),minted_coins);
    }

}