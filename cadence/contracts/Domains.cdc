import NonFungibleToken from "./interfaces/NonFungibleToken.cdc"
import FungibleToken from "./interfaces/FungibleToken.cdc"
import FlowToken from "./tokens/FlowToken.cdc"

// The contract defines Domains NFT Collection
pub contract Domains: NonFungibleToken {

    // Global vars
    pub let owners: {String: Address}
    pub let expirationTimes: {String: UFix64}
    // defines forbidden chars like . in domain name
    pub let forbiddenChars: String

    // Mapping for nameHash -> domain ID
    pub let nameHashToIDs: {String: UInt64}

    // A counter to track how many domains minted
    pub var totalSupply: UInt64

    // Events
    pub event DomainBioChanged(nameHash: String, bio: String)
    pub event DomainAddressChaged(nameHash: String, address: Address)
    pub event DomainMinted(id: UInt64, name: String, nameHash: String, expiresAt: UFix64, receiver: Address)
    // Emit when a domain is renewed or rented
    pub event DomainRenewed(id: UInt64, name: String, nameHash: String, expiresAt: UFix64, receiver: Address)

    // These are the events required by NonFungibleToken standard
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    // Storage, Public, and Private paths for Domains.Collection resource
    pub let DomainsStoragePath: StoragePath
    pub let DomainsPrivatePath: PrivatePath
    pub let DomainsPublicPath: PublicPath

    // Storage, Public, and Private paths for Domains.Registrar resource
    pub let RegistrarStoragePath: StoragePath
    pub let RegistrarPrivatePath: PrivatePath
    pub let RegistrarPublicPath: PublicPath

    // Event that implies a contract has been initialized
    // Required by the NonFungibleToken standard
    pub event ContractInitialized()

    init() {
        // Initial values for dictionaries is an empty dictionary
        self.owners = {}
        self.expirationTimes = {}
        self.nameHashToIDs = {}

        // Define forbidden characters for domain names
        self.forbiddenChars = "!@#$%^&*()<>? ./"
        // Initialize total supply to 0
        self.totalSupply = 0

        // Set the various paths to store `Domains.Collection` at in a user's account storage
        self.DomainsStoragePath = StoragePath(identifier: "flowNameServiceDomains") ?? panic("Could not set storage path")
        self.DomainsPrivatePath = PrivatePath(identifier: "flowNameServiceDomains") ?? panic("Could not set private path")
        self.DomainsPublicPath = PublicPath(identifier: "flowNameServiceDomains") ?? panic("Could not set public path")

        // Set the various paths to store `Domains.Registrar` in the admin account's storage
        self.RegistrarStoragePath = StoragePath(identifier: "flowNameServiceRegistrar") ?? panic("Could not set storage path")
        self.RegistrarPrivatePath = PrivatePath(identifier: "flowNameServiceRegistrar") ?? panic("Could not set private path")
        self.RegistrarPublicPath = PublicPath(identifier: "flowNameServiceRegistrar") ?? panic("Could not set public path")
        
        // self.account refers to the account where the smart contract lives
        // i.e. the admin account
        // 1. Create an empty Domains.Collection resource
        // 2. Save it to the admin account's storage path
        self.account.save(<- self.createEmptyCollection(), to: Domains.DomainsStoragePath)
    
        // 3. Link the Public resource interfaces that we are okay sharing with third-parties
        // to the public account storage from the main storage path
        // All objects in public paths can be accessed by anyone
        self.account.link<&Domains.Collection{NonFungibleToken.CollectionPublic, NonFungibleToken.Receiver, Domains.CollectionPublic}>(self.DomainsPublicPath, target: self.DomainsStoragePath)
        
        // 4. Link the overall resource (public + private) to the
        // private storage path from the main storage path
        // This allows us to create capabilities if necessary
        // This is needed because Capabilities can only be created from
        // public or private paths, not from the main storage path
        // for security reasons
        self.account.link<&Domains.Collection>(self.DomainsPrivatePath, target: self.DomainsStoragePath)

        // Now, get a capability from the private path for Domains.Collection
        // from the admin account
        // We will pass this onto the Registrar resource (to be created)
        // So it has access to the Private functions within Domains.Collection
        // Specifically, `mintDomain`
        let collectionCapability = self.account.getCapability<&Domains.Collection>(self.DomainsPrivatePath)
        
        // Create an empty FungibleToken.Vault for the FlowToken
        // This is the one and only time we utilize the FlowToken import
        let vault <- FlowToken.createEmptyVault()
        // Create a Registrar resource, and give it the Vault 
        // and the Private Collection Capability
        let registrar <- create Registrar(vault: <- vault, collection: collectionCapability)
        
        // Now save the Registrar resource in the admin account's main storage path
        self.account.save(<- registrar, to: self.RegistrarStoragePath)
    
        // Link the Public portion of the Registar to the public path
        // for the Registrar resource
        self.account.link<&Domains.Registrar{Domains.RegistrarPublic}>(self.RegistrarPublicPath, target: self.RegistrarStoragePath)
        // Link the overall resource (public + private) to the 
        // private path for the Registrar Resource
        self.account.link<&Domains.Registrar>(self.RegistrarPrivatePath, target: self.RegistrarStoragePath)

        // Emit the ContractInitialized event
        emit ContractInitialized()
    }

    // Struct to represent information about a FNS domain
    pub struct DomainInfo {
        // Public variables
        pub let id: UInt64
        pub let owner: Address
        pub let name: String
        pub let nameHash: String
        pub let expiresAt: UFix64
        pub let address: Address?
        pub let bio: String
        pub let createdAt: UFix64

        // Struct initializer
        init(
            id: UInt64,
            owner: Address,
            name: String,
            nameHash: String,
            expiresAt: UFix64,
            address: Address?,
            bio: String,
            createdAt: UFix64
        ) {
            self.id = id
            self.owner = owner
            self.name = name
            self.nameHash = nameHash
            self.expiresAt = expiresAt
            self.address = address
            self.bio = bio
            self.createdAt = createdAt
        }
    }

    // Public portion of the NFT
    pub resource interface DomainPublic {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        pub fun getBio(): String
        pub fun getAddress(): Address?
        pub fun getDomainName(): String
        pub fun getInfo(): DomainInfo
    }

    // Private portion of the NFT
    pub resource interface DomainPrivate {
        pub fun setBio(bio: String)
        pub fun setAddress(addr: Address)
    }

    // Helper functions
    // Checks if the domain is available
    pub fun isAvailable(nameHash: String): Bool {
        if self.owners[nameHash] == nil {
            return true
        }
        return self.isExpired(nameHash: nameHash)
    }

    // Returns the expiry time for the domain name
    pub fun getExpirationTime(nameHash: String): UFix64? {
        return self.expirationTimes[nameHash]
    }

    // Checks if domain name is expired
    pub fun isExpired(nameHash: String): Bool {
        let currTime: UFix64 = getCurrentBlock().timestamp
        let expTime: UFix64 = self.expirationTimes[nameHash]!
        if expTime != nil {
            return Int(currTime) >= Int(expTime)
        }
        return false
    }

    // Returns the entire `owners` dictionary
    pub fun getAllOwners(): {String: Address} {
        return self.owners
    }

    // Returns the all `expirationTimes` dictionary
    pub fun getAllExpirationTimes(): {String: UFix64} {
        return self.expirationTimes
    }

    // Get all nameHash to IDs
    pub fun getAllNameHashToIDs(): {String: UInt64} {
        return self.nameHashToIDs
    }

    // Update the owner of the domain
    access(account) fun updateOwner(nameHash: String, address: Address) {
        self.owners[nameHash] = address
    }

    // Update the expiration time of the domain
    access(account) fun updateExpirationTime(nameHash: String, expTime: UFix64) {
        self.expirationTimes[nameHash] = expTime
    }

    // Update nameHashToIDs
    access(account) fun updateNameHashToID(nameHash: String, id: UInt64) {
        self.nameHashToIDs[nameHash] = id
    }

    // Returns the domain name hash
    pub fun getDomainNameHash(name: String): String {
        // Making sure name doesn't have illegal characters
        let forbiddenCharsUTF8 = self.forbiddenChars.utf8
        let nameUTF8 = name.utf8

        for char in forbiddenCharsUTF8 {
            if nameUTF8.contains(char) {
                panic("Illegal domain name")
            }
        }

        // Calculate the SHA-256 hash and encode as hex string
        let nameHash: String = String.encodeHex(HashAlgorithm.SHA3_256.hash(nameUTF8))
        return nameHash
    }

    pub resource NFT: DomainPublic, DomainPrivate, NonFungibleToken.INFT {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        // access(self) implies that only the code within this resource
        // can read/modify this variable directly
        // This is similar to `private` in Solidity
        access(self) var address: Address?
        access(self) var bio: String

        init(id: UInt64, name: String, nameHash: String) {
            self.id = id
            self.name = name
            self.nameHash = nameHash
            self.createdAt = getCurrentBlock().timestamp
            self.address = nil
            self.bio = ""
        }

        pub fun getBio(): String {
            return self.bio
        }

        pub fun getAddress(): Address? {
            return self.address
        }

        pub fun getDomainName(): String {
            return self.name.concat(".fns")
        }

        pub fun setBio(bio: String) {
            // This is like require in Solidity
            pre {
                Domains.isExpired(nameHash: self.nameHash) == false : "Domain is expired"
            }
            self.bio = bio
            emit DomainBioChanged(nameHash: self.nameHash, bio: self.bio)
        }

        pub fun setAddress(addr: Address) {
            pre {
                Domains.isExpired(nameHash: self.nameHash) == false : "Domain is expired"
            }
            self.address = addr
            emit DomainAddressChaged(nameHash: self.nameHash, address: addr)
        }

        pub fun getInfo(): DomainInfo {
            let owner: Address = Domains.owners[self.nameHash]!

            return DomainInfo(
                id: self.id,
                owner: owner,
                name: self.getDomainName(),
                nameHash: self.nameHash,
                expiresAt: Domains.expirationTimes[self.nameHash]!,
                address: self.address,
                bio: self.bio,
                createdAt: self.createdAt
            )
        }
    }

    pub resource interface CollectionPublic {
        pub fun borrowDomain(id: UInt64): &{Domains.DomainPublic}
    }

    pub resource interface CollectionPrivate {
        access(account) fun mintDomain(name: String, nameHash: String, expiresAt: UFix64, receiver: Capability<&{NonFungibleToken.Receiver}>)
        pub fun borrowDomainPrivate(id: UInt64): &Domains.NFT
    }

    pub resource Collection: CollectionPublic, CollectionPrivate, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // Dictionary of TokenID -> NFT Resource
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init() {
            // Initialize an empty resource
            self.ownedNFTs <- {}
        }

        // function required by NonFungibleToken.Provider
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let domain: @NonFungibleToken.NFT <- self.ownedNFTs.remove(key: withdrawID)
                ?? panic("NFT not found in collection")
            emit Withdraw(id: withdrawID, from: self.owner?.address)
            return <- domain
        }

        // function required by NonFungibleToken.Receiver
        pub fun deposit(token: @NonFungibleToken.NFT) {
            // Typecast the generic NFT resource into Domains.NFT resource
            let domain: @Domains.NFT <- token as! @Domains.NFT
            let id = domain.id
            let nameHash = domain.nameHash

            if Domains.isExpired(nameHash: nameHash) {
                panic("Domain is expired")
            }

            Domains.updateOwner(nameHash: nameHash, address: self.owner!.address)
            let oldToken: @NonFungibleToken.NFT? <- self.ownedNFTs[id] <- domain
            destroy oldToken
        }

        // NonFungibleToken.CollectionPublic
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        // Domains.CollectionPublic
        pub fun borrowDomain(id: UInt64): &{Domains.DomainPublic} {
            pre {
                self.ownedNFTs[id] != nil : "Domain does not exist"
            }
            let token: auth &NonFungibleToken.NFT = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            return token as! &Domains.NFT
        }

        // Domains.CollectionPrivate
        access(account) fun mintDomain(name: String, nameHash: String, expiresAt: UFix64, receiver: Capability<&{NonFungibleToken.Receiver}>) {
            pre {
                Domains.isAvailable(nameHash: nameHash) : "Domain not available"
            }

            let domain: @Domains.NFT <- create Domains.NFT(
                id: Domains.totalSupply,
                name: name,
                nameHash: nameHash
            )

            Domains.updateOwner(nameHash: nameHash, address: receiver.address)
            Domains.updateExpirationTime(nameHash: nameHash, expTime: expiresAt)
            Domains.updateNameHashToID(nameHash: nameHash, id: domain.id)
            Domains.totalSupply = Domains.totalSupply + 1

            emit DomainMinted(id: domain.id, name: name, nameHash: nameHash, expiresAt: expiresAt, receiver: receiver.address)

            receiver.borrow()!.deposit(token: <- domain)
        }

        pub fun borrowDomainPrivate(id: UInt64): &Domains.NFT {
            pre {
                self.ownedNFTs[id] != nil : "Domain does not exist"
            }

            let ref: auth &NonFungibleToken.NFT = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            return ref as! &Domains.NFT
        }

        destroy() {
            destroy self.ownedNFTs
        }
    }

    pub resource interface RegistrarPublic {
        // defines minimum time duration a domain must be rented
        pub let minRentDuration: UFix64
        // defines max length of a domain name (excluding .fns)
        pub let maxDomainLength: Int
        pub let prices: {Int: UFix64}

        pub fun renewDomain(domain: &Domains.NFT, duration: UFix64, feeTokens: @FungibleToken.Vault)
        pub fun registerDomain(name: String, duration: UFix64, feeTokens: @FungibleToken.Vault, receiver: Capability<&{NonFungibleToken.Receiver}>)
        pub fun getPrices(): {Int: UFix64}
        pub fun getVaultBalance(): UFix64
    }

    pub resource interface RegistrarPrivate {
        pub fun updateRentVault(vault: @FungibleToken.Vault)
        pub fun withdrawVault(receiver: Capability<&{FungibleToken.Receiver}>, amount: UFix64)
        pub fun setPrices(key: Int, val: UFix64)
    }

    pub resource Registrar: RegistrarPublic, RegistrarPrivate {
        // Vars defined in the interface
        pub let minRentDuration: UFix64
        pub let maxDomainLength: Int
        pub let prices: {Int: UFix64}

        // A reference to the Vault used for depositing Flow tokens we receive
        // `priv` variables cannot be defined in interfaces
        // `priv` = `private`. It is a shorthand for access(self)
        priv var rentVault: @FungibleToken.Vault

        // A capability for the Domains.Collection resource owned by the account
        // Only the account has access to it
        // We will use this to access the account-only `mintDomain` function
        // Within the Collection owned by our smart contract account
        access(account) var domainsCollection: Capability<&Domains.Collection>

        init(vault: @FungibleToken.Vault, collection: Capability<&Domains.Collection>) {
            // Represents 1 year in seconds
            self.minRentDuration = UFix64(365 * 24 * 60 * 60)
            self.maxDomainLength = 30
            self.prices = {}

            self.rentVault <- vault
            self.domainsCollection = collection
        }

        pub fun renewDomain(domain: &Domains.NFT, duration: UFix64, feeTokens: @FungibleToken.Vault) {
            // We don't need to check if the user owns this domain
            // because they are providing us a full reference to Domains.NFT
            // through the first argument.
            // They could not have done this if they did not own the domain
            
            var len: Int = domain.name.length
            // If the length of the domain name is >10,
            // Make the arbitrary decision to price it the same way
            // as if it was 10 characters long
            if len > 10 {
                len = 10
            }

            // Get the price per second of rental for this length of domain
            let price: UFix64? = self.getPrices()[len]

            // Ensure that the duration to rent for isn't less than the minimum
            if duration < self.minRentDuration {
                panic("Domain must be registered for at least the minimum duration: ".concat(self.minRentDuration.toString()))
            }

            // Ensure that the admin has set a price for this domain length
            if price == 0.0 || price == nil {
                panic("Price has not been set for this length of domain")
            }

            // Calculate total rental cost (price * duration)
            let rentCost: UFix64 = price! * duration
            // Check the balance of the Vault given to us by the user
            // This is their way of sending us tokens through the transaction
            let feeSent: UFix64 = feeTokens.balance

            // Ensure they've sent >= tokens as required
            if feeSent < rentCost {
                panic("You did not send enough FLOW tokens. Expected: ".concat(rentCost.toString()))
            }

            // If yes, deposit those tokens into our own rentVault
            self.rentVault.deposit(from: <- feeTokens)

            // Calculate the new expiration date for this domain
            // Add duration of rental to current expiry date
            // and update the expiration time
            let newExpTime: UFix64 = Domains.getExpirationTime(nameHash: domain.nameHash)! + duration
            Domains.updateExpirationTime(nameHash: domain.nameHash, expTime: newExpTime)

            // emit the DomainRenewed event
            emit DomainRenewed(id: domain.id, name: domain.name, nameHash: domain.nameHash, expiresAt: newExpTime, receiver: domain.owner!.address)
        }

        pub fun registerDomain(name: String, duration: UFix64, feeTokens: @FungibleToken.Vault, receiver: Capability<&{NonFungibleToken.Receiver}>) {
            // Ensure the domain name is not longer than the max length allowed
            pre {
                name.length <= self.maxDomainLength : "Domain name is too long"
            }

            // Hash the name and get the nameHash
            let nameHash = Domains.getDomainNameHash(name: name)

            // Ensure the domain is available for sale
            if Domains.isAvailable(nameHash: nameHash) == false {
                panic("Domain is not available")
            }

            // Same as renew, price any domain >10 characters the same way
            // as a domain with 10 characters
            var len = name.length
            if len > 10 {
                len = 10
            }

            // All the calculations are the same as renew
            let price = self.getPrices()[len]

            if duration < self.minRentDuration {
                panic("Domain must be registered for at least the minimum duration: ".concat(self.minRentDuration.toString()))
            }

            if price == 0.0 || price == nil {
                panic("Price has not been set for this length of domain")
            }

            let rentCost = price! * duration
            let feeSent = feeTokens.balance

            if feeSent < rentCost {
                panic("You did not send enough FLOW tokens. Expected: ".concat(rentCost.toString()))
            }

            self.rentVault.deposit(from: <- feeTokens)

            // Calculate the expiry time for the domain by adding duration
            // to the current timestamp
            let expirationTime = getCurrentBlock().timestamp + duration

            // Use the domainsCollection capability of the admin to mint the new domain
            // and transfer it to the receiver
            self.domainsCollection.borrow()!.mintDomain(name: name, nameHash: nameHash, expiresAt: expirationTime, receiver: receiver)

            // DomainMinted event is emitted from mintDomain
        }

        // Return the prices dictionary
        pub fun getPrices(): {Int: UFix64} {
            return self.prices
        }

        // Return the balance of our rentVault
        pub fun getVaultBalance(): UFix64 {
            return self.rentVault.balance
        }

        // Update the rentVault to point to a different vault
        pub fun updateRentVault(vault: @FungibleToken.Vault) {
            // Make sure current vault doesn't have any remaining tokens before updating it
            pre {
                self.rentVault.balance == 0.0 : "Withdraw balance from old vault before updating"
            }

            // Simultaneously move the old vault out, and move the new vault in
            let oldVault <- self.rentVault <- vault
            // Destroy the old vault
            destroy oldVault
        }

        // Move tokens from our rentVault to the given FungibleToken.Receiver
        pub fun withdrawVault(receiver: Capability<&{FungibleToken.Receiver}>, amount: UFix64) {
            let vault = receiver.borrow()!
            vault.deposit(from: <- self.rentVault.withdraw(amount: amount))
        }

        // Update the prices of domains for a given length
        pub fun setPrices(key: Int, val: UFix64) {
            self.prices[key] = val
        }

        destroy() {
            destroy self.rentVault
        }
    }

    // Smart Contract public functions and initializers

    // creates empty collection
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        let collection: @Domains.Collection <- create Collection()
        return <- collection
    }

    // Returns the rental cost so it can be used by frontend
    pub fun getRentCost(name: String, duration: UFix64): UFix64 {
        var len: Int = name.length
        if len > 10 {
            len = 10
        }

        let price = self.getPrices()[len]
        let rentCost = price! * duration
        return rentCost
    }

    pub fun getVaultBalance(): UFix64 {
        let cap = self.account.getCapability<&Domains.Registrar{Domains.RegistrarPublic}>(Domains.RegistrarPublicPath)
        let registrar = cap.borrow() ?? panic("Could not borrow registrar public")
        return registrar.getVaultBalance()
    }

    pub fun registerDomain(name: String, duration: UFix64, feeTokens: @FungibleToken.Vault, receiver: Capability<&{NonFungibleToken.Receiver}>) {
        let cap = self.account.getCapability<&Domains.Registrar{Domains.RegistrarPublic}>(self.RegistrarPublicPath)
        let registrar = cap.borrow() ?? panic("Could not borrow registrar")
        registrar.registerDomain(name: name, duration: duration, feeTokens: <- feeTokens, receiver: receiver)
    }

    pub fun renewDomain(domain: &Domains.NFT, duration: UFix64, feeTokens: @FungibleToken.Vault) {
        let cap = self.account.getCapability<&Domains.Registrar{Domains.RegistrarPublic}>(self.RegistrarPublicPath)
        let registrar = cap.borrow() ?? panic("Could not borrow registrar")
        registrar.renewDomain(domain: domain, duration: duration, feeTokens: <- feeTokens)
    }

    pub fun getPrices(): {Int: UFix64} {
        let cap = self.account.getCapability<&Domains.Registrar{Domains.RegistrarPublic}>(Domains.RegistrarPublicPath)
        let collection = cap.borrow() ?? panic("Could not borrow collection")
        return collection.getPrices()
    }
}