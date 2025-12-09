module deployer_addr::options {
    
    // -- imports -- 
    use std::signer;
    use std::error;
    use std::vector;
    use std::debug;

    use aptos_framework::object::{Self,DeleteRef,TransferRef,ExtendRef,Object};
    use aptos_framework::event::{Self};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::account;

    // -- constants error codes --

    // object names 
    const NAME: vector<u8> = b"OpitonsConfigObjects";

    // option types
    const CALL_OPTION:u64 = 0;
    const PUT_OPTION:u64 = 1; 

    // option states
    const STATE_ACTIVE:u64 = 1;
    const STATE_EXPIRED:u64 = 2;
    const STATE_SETTLED:u64 = 3;
    const STATE_EXCERCISED:u64 = 4;


    // -- resources and objects --
    // 1. options config: deployer address .. confugration and maintaining the list of options.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsConfig has key {
        admin: address,
        options_created: u64,
        options_addreses: vector<address>,
        min_expiry_sec: u64,
        max_expiry_sec: u64,
        extendRef:ExtendRef
    }

    // 2. option drtail: createor .. premium, amount , id , expiry timestamp.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsDetails has key {
        id: u64,
        creator: address,
        premium: u64,
        amount: u64,
        creation_timestamp: u64,
        expiry_timestamp: u64,
        options_type: u8, // 0 for call & 1 for put
        option_state: u8,
        strike_price: u64,
        deleteRef: DeleteRef,
        transferRef: TransferRef

    }

    // 3. options vault: coin<Aptos Coin>.
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct OptionsVault has key {
        funds : Coin<AptosCoin>
    }

   // -- event and structs --
    // 1. create option 
    // 2. buy option 
    // 3. excersised option 
    // 4. settled option 


    // -- entry functions and view fuctions -- 
    
    // 1. init_module
    entry fun init_module(deployer: &signer){
        let deployer_addr = signer::address_of(deployer);

        let constructor_ref = object::create_named_object(deployer,NAME);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer,OptionsConfig{
            extendRef: extend_ref,
            admin: deployer_addr,
            options_created: 0,
            options_addreses: vector::empty<address>(),
            min_expiry_sec: 600,
            max_expiry_sec: 3600,
        });
    }


    // tests 
}