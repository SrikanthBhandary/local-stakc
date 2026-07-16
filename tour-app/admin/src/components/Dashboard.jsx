import "./dashboard.css";

import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";


const API_URL =`${import.meta.env.VITE_API_URL}/admin/enquiries`;


export default function Dashboard() {

    const auth = useAuth();

    const [enquiries, setEnquiries] = useState([]);

    const [loading, setLoading] = useState(true);

    const [error, setError] = useState(null);



    useEffect(() => {

        async function loadEnquiries() {

            try {

                const response = await fetch(API_URL, {

                    headers: {

                        Authorization: `Bearer ${auth.accessToken}`

                    }

                });


                if (!response.ok) {

                    throw new Error(
                        `API failed ${response.status}`
                    );

                }


                const data = await response.json();


                setEnquiries(data.items || []);

            }

            catch(err) {

                console.error(err);

                setError(err.message);

            }

            finally {

                setLoading(false);

            }

        }


        loadEnquiries();


    }, [auth.accessToken]);




    return (

        <div className="dashboard-layout">


            <aside className="sidebar">


                <div className="logo">

                    <h2>
                        🏔 HighPasses
                    </h2>

                </div>


                <nav>

                    <a href="#" className="active">
                        Dashboard
                    </a>

                    <a href="#">
                        Enquiries
                    </a>


                    <a href="#">
                        Tours
                    </a>


                    <a href="#">
                        Settings
                    </a>


                </nav>


            </aside>



            <main className="dashboard-main">


                <header className="dashboard-header">


                    <h1>
                        Dashboard
                    </h1>


                    <button onClick={auth.logout}>
                        Logout
                    </button>


                </header>




                <section className="cards">


                    <div className="card">

                        <h3>
                            Total Enquiries
                        </h3>


                        <span>
                            {enquiries.length}
                        </span>

                    </div>



                    <div className="card">

                        <h3>
                            Pending
                        </h3>


                        <span>
                            {
                                enquiries.filter(
                                    e => e.status === "pending"
                                ).length
                            }
                        </span>

                    </div>



                    <div className="card">


                        <h3>
                            Email Sent
                        </h3>


                        <span>
                            {
                                enquiries.filter(
                                    e => e.emailSent
                                ).length
                            }
                        </span>


                    </div>


                </section>




                <section className="table-card">


                    <h2>
                        Recent Enquiries
                    </h2>



                    {
                        loading &&
                        <p>
                            Loading enquiries...
                        </p>
                    }



                    {
                        error &&
                        <p>
                            Error: {error}
                        </p>
                    }




                    {
                        !loading && !error && (

                            <table>


                                <thead>

                                    <tr>

                                        <th>
                                            Name
                                        </th>


                                        <th>
                                            Email
                                        </th>


                                        <th>
                                            Tour
                                        </th>


                                        <th>
                                            Travelers
                                        </th>


                                        <th>
                                            Status
                                        </th>


                                    </tr>

                                </thead>



                                <tbody>


                                {
                                    enquiries.map(item => (

                                        <tr key={item.id}>


                                            <td>
                                                {item.name}
                                            </td>


                                            <td>
                                                {item.email}
                                            </td>


                                            <td>
                                                {item.tour}
                                            </td>


                                            <td>
                                                {item.travelers}
                                            </td>


                                            <td>
                                                {item.status}
                                            </td>


                                        </tr>

                                    ))
                                }


                                </tbody>


                            </table>

                        )
                    }



                </section>



            </main>


        </div>

    );

}