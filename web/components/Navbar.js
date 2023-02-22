import Link from "next/link"
import { useAuth } from "@/contexts/AuthContext"
import "../flow/config"
import { MdNightlightRound, MdWbSunny} from "react-icons/md"

function Navbar() {
  // Use AuthContext to get the values for currentUser and helper functions logiIn and logOut
  const { currentUser, logIn, logOut } = useAuth()
  return (
        <nav className="grid">
            <ul>
                <li><strong>FLOW NAMESERVICE (FNS)</strong></li>
            </ul>
            <ul>
                <li><Link href="/">Home</Link></li>
                <li><Link href="/purchase">Purchase</Link></li>
                <li><Link href="/manage">Manage</Link></li>
                <li><button onClick={currentUser.addr ? logOut : logIn}>
                    {currentUser.addr ? "Log Out" : "Login"}
                </button></li>
                <li><button id="theme-toggle" type="button" className="theme-toggle-button" data-theme-switcher="light">
                  <MdNightlightRound fill='black' id="theme-toggle-dark-icon" />
                  <MdWbSunny fill='white' id="theme-toggle-light-icon" />
                </button></li>
            </ul>
        </nav>
    )
}

export default Navbar
