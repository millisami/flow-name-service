import Link from "next/link"
import { useAuth } from "@/contexts/AuthContext"
import "../flow/config"
import styles from "@/styles/Navbar.module.css"

function Navbar() {
  // Use AuthContext to get the values for currentUser and helper functions logiIn and logOut
  const { currentUser, logIn, logOut } = useAuth()
  return (
        <div className={styles.navbar}>
            <Link href="/">Home</Link>
            <Link href="/purchase">Purchase</Link>
            <Link href="/manage">Manage</Link>
            <button onClick={currentUser.addr ? logOut : logIn}>
                {currentUser.addr ? "Log Out" : "Login"}
            </button>
        </div>
    )
}

export default Navbar
